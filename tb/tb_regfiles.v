// =============================================================================
// tb_regfiles.v - tests the vector and scalar register files
// =============================================================================
// What we check:
//   Vector register file (8 registers x 128 bits)
//     * every register can be written and read back through BOTH read ports
//     * nothing is written when write_en = 0
//     * reading a register while writing it gives the old value until the
//       clock edge, then the new value
//     * 2000 random reads/writes match a simple copy kept by the testbench
//   Scalar register file (8 registers x 32 bits)
//     * s0 always reads 0, even after we try to write it
//     * s1..s7 write and read back, debug port shows the same values
//     * 2000 random reads/writes match the testbench copy
//
// Run:  make tb_regfiles
// =============================================================================

`timescale 1ns/1ps

module tb_regfiles;

    localparam LANES = 8;
    localparam W     = 16;
    localparam VLEN  = LANES * W;

    reg clk = 1'b0;
    always #5 clk = ~clk;        // 10 ns clock period

    integer errors = 0;
    integer checks = 0;
    integer seed   = 7;
    integer i, r;

    // ---- Vector register file -------------------------------------------------
    reg  [2:0]      v_ra, v_rb, v_wa;
    reg             v_we;
    reg  [VLEN-1:0] v_wd;
    wire [VLEN-1:0] v_qa, v_qb;

    vec_regfile #(.LANES(LANES), .W(W)) u_vrf (
        .clk(clk),
        .read_addr_a(v_ra), .read_data_a(v_qa),
        .read_addr_b(v_rb), .read_data_b(v_qb),
        .write_en(v_we), .write_addr(v_wa), .write_data(v_wd)
    );

    // ---- Scalar register file -------------------------------------------------
    reg  [2:0]  s_ra, s_rb, s_wa, s_dbg;
    reg         s_we;
    reg  [31:0] s_wd;
    wire [31:0] s_qa, s_qb, s_qdbg;

    scalar_regfile u_srf (
        .clk(clk),
        .read_addr_a(s_ra), .read_data_a(s_qa),
        .read_addr_b(s_rb), .read_data_b(s_qb),
        .write_en(s_we), .write_addr(s_wa), .write_data(s_wd),
        .debug_addr(s_dbg), .debug_data(s_qdbg)
    );

    // Our own copies of what the registers should hold.
    reg [VLEN-1:0] v_model [0:7];
    reg [31:0]     s_model [0:7];

    // Compare a value with the expected one and count errors.
    task expect_eq;
        input [VLEN-1:0] got, want;
        input [8*24-1:0] what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH %0s: got %h want %h", what, got, want);
            end
        end
    endtask

    // A different 128-bit pattern for each register number.
    function [VLEN-1:0] pattern;
        input [2:0] n;
        pattern = {LANES{8'hA0 + n, 8'h10 * n + 8'h05}};
    endfunction

    initial begin
        v_we = 0; s_we = 0;
        v_ra = 0; v_rb = 0; v_wa = 0; v_wd = 0;
        s_ra = 0; s_rb = 0; s_wa = 0; s_wd = 0; s_dbg = 0;
        $display("tb_regfiles: vector %0d x %0d bits, scalar 8 x 32 bits", 8, VLEN);

        // ================= Vector register file =================

        // 1. Write a unique pattern into every register.
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            v_we = 1; v_wa = i; v_wd = pattern(i);
            v_model[i] = pattern(i);
        end
        @(negedge clk) v_we = 0;

        // 2. Read every register back through port A and port B.
        //    Port B reads in reverse order so both ports move independently.
        for (i = 0; i < 8; i = i + 1) begin
            v_ra = i; v_rb = 7 - i; #1;
            expect_eq(v_qa, v_model[i],     "vreg port A");
            expect_eq(v_qb, v_model[7 - i], "vreg port B");
        end

        // 3. write_en = 0 must not change anything.
        @(negedge clk);
        v_we = 0; v_wa = 3; v_wd = {VLEN{1'b1}};
        @(negedge clk);
        v_ra = 3; #1;
        expect_eq(v_qa, v_model[3], "vreg write_en=0");

        // 4. Read while writing the same register: old value before the edge,
        //    new value after it.
        @(negedge clk);
        v_we = 1; v_wa = 5; v_wd = {LANES{16'hBEEF}}; v_ra = 5; #1;
        expect_eq(v_qa, v_model[5], "vreg read-before-edge");
        @(posedge clk); #1;
        v_model[5] = {LANES{16'hBEEF}};
        expect_eq(v_qa, v_model[5], "vreg read-after-edge");
        @(negedge clk) v_we = 0;

        // 5. Random writes and reads.
        for (r = 0; r < 2000; r = r + 1) begin
            @(negedge clk);
            v_we = $random(seed);
            v_wa = $random(seed);
            v_wd = {$random(seed), $random(seed), $random(seed), $random(seed)};
            v_ra = $random(seed);
            v_rb = $random(seed);
            #1;
            expect_eq(v_qa, v_model[v_ra], "vreg random A");
            expect_eq(v_qb, v_model[v_rb], "vreg random B");
            @(posedge clk);
            if (v_we) v_model[v_wa] = v_wd;
        end
        @(negedge clk) v_we = 0;

        // ================= Scalar register file =================

        for (i = 0; i < 8; i = i + 1) s_model[i] = 0;

        // 6. Write s0..s7 (including s0, which must ignore the write).
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            s_we = 1; s_wa = i; s_wd = 32'h1000_0000 * (i + 1) + i;
            if (i != 0) s_model[i] = s_wd;
        end
        @(negedge clk) s_we = 0;

        // 7. Read back through A, B and the debug port. s0 must be 0.
        for (i = 0; i < 8; i = i + 1) begin
            s_ra = i; s_rb = 7 - i; s_dbg = i; #1;
            expect_eq(s_qa,   s_model[i],     "sreg port A");
            expect_eq(s_qb,   s_model[7 - i], "sreg port B");
            expect_eq(s_qdbg, s_model[i],     "sreg debug port");
        end
        s_ra = 0; #1;
        expect_eq(s_qa, 32'd0, "s0 hard-wired zero");

        // 8. Random writes and reads.
        for (r = 0; r < 2000; r = r + 1) begin
            @(negedge clk);
            s_we  = $random(seed);
            s_wa  = $random(seed);
            s_wd  = $random(seed);
            s_ra  = $random(seed);
            s_rb  = $random(seed);
            s_dbg = $random(seed);
            #1;
            expect_eq(s_qa,   s_model[s_ra],  "sreg random A");
            expect_eq(s_qb,   s_model[s_rb],  "sreg random B");
            expect_eq(s_qdbg, s_model[s_dbg], "sreg random debug");
            @(posedge clk);
            if (s_we && s_wa != 0) s_model[s_wa] = s_wd;
        end

        $display("tb_regfiles: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule
