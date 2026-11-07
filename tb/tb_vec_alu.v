// =============================================================================
// tb_vec_alu.v - tests the lane ALU and the parallel ALU array
// =============================================================================
// How the test works:
//   1. We build an 8-lane ALU array (the "device under test", DUT).
//   2. We feed it inputs: first hand-picked tricky values, then thousands of
//      random ones.
//   3. For every lane we work out the correct answer with our own simple
//      model (written differently from the RTL, using plain integer maths)
//      and compare. Any difference is printed and counted as an error.
//   4. At the end we print a coverage table: how many times each operation
//      was checked, and whether its interesting cases were seen.
//
// Run:  make tb_vec_alu
// =============================================================================

`timescale 1ns/1ps
`include "simd_defs.vh"

module tb_vec_alu;

    localparam LANES = 8;
    localparam W     = 16;
    localparam NUM_OPS = 14;
    localparam RANDOM_ROUNDS = 2000;     // random vectors per operation

    // ---- DUT ------------------------------------------------------------
    reg  [3:0]         op;
    reg  [LANES*W-1:0] a, b;
    wire [LANES*W-1:0] y;

    vec_alu_array #(.LANES(LANES), .W(W)) dut (.op(op), .a(a), .b(b), .y(y));

    // ---- Reference model --------------------------------------------------
    // Uses 32-bit integers, then keeps the low W bits. Because it is written
    // in a different way from the RTL, a mistake in one will not hide the
    // same mistake in the other.
    function [W-1:0] model;
        input [3:0]   f;
        input [W-1:0] x, z;
        integer sx, sz, ux, uz, n;
        begin
            sx = $signed(x);   sz = $signed(z);    // signed readings
            ux = x;            uz = z;             // unsigned readings
            n  = uz % W;                           // shift amount
            case (f)
                `ALU_ADD:  model = sx + sz;
                `ALU_SUB:  model = sx - sz;
                `ALU_AND:  model = x & z;
                `ALU_OR:   model = x | z;
                `ALU_XOR:  model = x ^ z;
                `ALU_SLL:  model = ux * (1 << n);          // shift left = multiply by 2^n
                `ALU_SRL:  model = ux / (1 << n);          // shift right = divide by 2^n
                `ALU_SRA:  model = sx >>> n;               // 32-bit signed shift, then cut
                `ALU_MUL:  model = sx * sz;
                `ALU_SEQ:  model = (ux == uz) ? -1 : 0;
                `ALU_SLT:  model = (sx <  sz) ? -1 : 0;
                `ALU_SLTU: model = (ux <  uz) ? -1 : 0;
                `ALU_MIN:  model = (sx <  sz) ? x : z;
                `ALU_MAX:  model = (sx <  sz) ? z : x;
                default:   model = 0;
            endcase
        end
    endfunction

    // ---- Bookkeeping ----------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer seed   = 2026;
    integer op_checks [0:15];    // how many lane checks per operation
    integer op_true   [0:15];    // compare ops: times the answer was "true"
    integer op_false  [0:15];    // compare ops: times the answer was "false"

    // Check all lanes of the current inputs against the model.
    task check_all_lanes;
        integer lane;
        reg [W-1:0] want, got;
        begin
            #1;   // let the combinational logic settle
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                want = model(op, a[lane*W +: W], b[lane*W +: W]);
                got  = y[lane*W +: W];
                checks = checks + 1;
                op_checks[op] = op_checks[op] + 1;
                if (want == {W{1'b1}}) op_true[op]  = op_true[op]  + 1;
                if (want == {W{1'b0}}) op_false[op] = op_false[op] + 1;
                if (got !== want) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("  MISMATCH op=%0d lane=%0d a=%h b=%h got=%h want=%h",
                                 op, lane, a[lane*W +: W], b[lane*W +: W], got, want);
                end
            end
        end
    endtask

    // Hand-picked tricky values: zero, one, -1, biggest, smallest, patterns.
    reg [W-1:0] corner [0:7];
    integer i, j, k, r;

    initial begin
        corner[0] = 16'h0000;  corner[1] = 16'h0001;  corner[2] = 16'hFFFF;
        corner[3] = 16'h7FFF;  corner[4] = 16'h8000;  corner[5] = 16'h00FF;
        corner[6] = 16'h5555;  corner[7] = 16'hAAAA;
        for (i = 0; i < 16; i = i + 1) begin
            op_checks[i] = 0; op_true[i] = 0; op_false[i] = 0;
        end

        $display("tb_vec_alu: %0d lanes x %0d bits", LANES, W);

        // ---- 1. Every pair of corner values, for every operation ------------
        // Lane k gets corner value pair (i, k) so each lane sees different data.
        for (k = 0; k < NUM_OPS; k = k + 1) begin
            op = k;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < LANES; j = j + 1) begin
                    a[j*W +: W] = corner[i];
                    b[j*W +: W] = corner[j % 8];
                end
                check_all_lanes;
            end
        end

        // ---- 2. Every shift amount 0..15, plus amounts above 15 --------------
        // Only the low 4 bits count, so shifting by 17 must act like 1.
        for (k = `ALU_SLL; k <= `ALU_SRA; k = k + 1) begin
            op = k;
            for (i = 0; i < 24; i = i + 1) begin
                for (j = 0; j < LANES; j = j + 1) begin
                    a[j*W +: W] = (j % 2) ? 16'h8421 : 16'hF00F;
                    b[j*W +: W] = i;
                end
                check_all_lanes;
            end
        end

        // ---- 3. Lanes must not leak into each other --------------------------
        // FFFF + 1 overflows inside a lane; the carry must NOT spill into the
        // next lane. Every lane should read exactly 0.
        op = `ALU_ADD;
        a = {LANES{16'hFFFF}};
        b = {LANES{16'h0001}};
        check_all_lanes;
        if (y !== {LANES*W{1'b0}}) begin
            errors = errors + 1;
            $display("  CARRY LEAK between lanes: y=%h", y);
        end

        // ---- 4. Random inputs ----------------------------------------------------
        for (k = 0; k < NUM_OPS; k = k + 1) begin
            op = k;
            for (r = 0; r < RANDOM_ROUNDS; r = r + 1) begin
                for (j = 0; j < LANES; j = j + 1) begin
                    a[j*W +: W] = $random(seed);
                    // Mix in some equal pairs so SEQ sees "true" often enough.
                    b[j*W +: W] = (r % 8 == 0) ? a[j*W +: W] : $random(seed);
                end
                check_all_lanes;
            end
        end

        // ---- 5. Unused op codes must give zero -------------------------------
        for (k = 14; k < 16; k = k + 1) begin
            op = k;
            a = {LANES{16'h1234}};
            b = {LANES{16'h4321}};
            check_all_lanes;
        end

        // ---- Coverage report ------------------------------------------------------
        $display("");
        // "true / false" only matters for the compare ops, so the others show "-".
        $display("  op   name   lane checks   true   false");
        for (k = 0; k < NUM_OPS; k = k + 1)
            if (k >= `ALU_SEQ && k <= `ALU_SLTU)
                $display("  %2d   %-5s  %11d  %5d  %6d", k, op_name(k), op_checks[k],
                         op_true[k], op_false[k]);
            else
                $display("  %2d   %-5s  %11d      -       -", k, op_name(k), op_checks[k]);
        // Every compare op must have produced both answers at least once.
        for (k = `ALU_SEQ; k <= `ALU_SLTU; k = k + 1)
            if (op_true[k] == 0 || op_false[k] == 0) begin
                errors = errors + 1;
                $display("  COVERAGE HOLE: op %0d never produced both true and false", k);
            end

        $display("");
        $display("tb_vec_alu: %0d lane checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

    // Short names for the coverage table.
    function [8*5-1:0] op_name;
        input [3:0] f;
        case (f)
            0: op_name = "ADD";   1: op_name = "SUB";   2: op_name = "AND";
            3: op_name = "OR";    4: op_name = "XOR";   5: op_name = "SLL";
            6: op_name = "SRL";   7: op_name = "SRA";   8: op_name = "MUL";
            9: op_name = "SEQ";  10: op_name = "SLT";  11: op_name = "SLTU";
           12: op_name = "MIN";  13: op_name = "MAX";
           default: op_name = "-";
        endcase
    endfunction

endmodule
