// =============================================================================
// tb_lane_combiner.v - tests the lane mux and the result combiner
// =============================================================================
// What we check:
//   Lane mux
//     * use_scalar = 0: every lane passes its own vector element through
//     * use_scalar = 1: every lane receives the same scalar value
//   Result combiner
//     * vector_result is exactly the lane inputs
//     * sum_result equals the lanes added one by one (a simple loop, so it
//       checks the adder TREE against a plain chain)
//     * the extreme cases: all lanes at the largest and smallest value
//
// LANES is a parameter, so the Makefile runs this test for 1, 2, 4 and 8 lanes.
//
// Run:  make tb_lane_combiner
// =============================================================================

`timescale 1ns/1ps

module tb_lane_combiner;

    parameter LANES = 8;
    localparam W = 16;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 11;
    integer r, j;

    // ---- Lane mux --------------------------------------------------------------
    reg                use_scalar;
    reg  [LANES*W-1:0] vector_b;
    reg  [W-1:0]       scalar_b;
    wire [LANES*W-1:0] lane_b;

    lane_mux #(.LANES(LANES), .W(W)) u_mux (
        .use_scalar(use_scalar), .vector_b(vector_b),
        .scalar_b(scalar_b), .lane_b(lane_b)
    );

    // ---- Result combiner -----------------------------------------------------------
    reg  [LANES*W-1:0] lanes_in;
    wire [LANES*W-1:0] vector_result;
    wire [31:0]        sum_result;

    result_combiner #(.LANES(LANES), .W(W)) u_comb (
        .lane_results(lanes_in), .vector_result(vector_result), .sum_result(sum_result)
    );

    // Reference sum: add the lanes one at a time, each read as a signed number.
    function [31:0] chain_sum;
        input [LANES*W-1:0] v;
        integer n, total;
        begin
            total = 0;
            for (n = 0; n < LANES; n = n + 1)
                total = total + $signed(v[n*W +: W]);
            chain_sum = total;
        end
    endfunction

    task check;
        input [LANES*W-1:0] got, want;
        input [8*20-1:0]    what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10) $display("  MISMATCH %0s: got %h want %h", what, got, want);
            end
        end
    endtask

    task check_combiner;
        begin
            #1;
            check(vector_result, lanes_in, "vector_result");
            // The sum is always 32 bits, so compare it on its own at full width
            // (the check task above is only LANES*W bits wide: 16 bits for 1 lane).
            checks = checks + 1;
            if (sum_result !== chain_sum(lanes_in)) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH sum_result: got %h want %h", sum_result, chain_sum(lanes_in));
            end
        end
    endtask

    initial begin
        $display("tb_lane_combiner: %0d lanes x %0d bits", LANES, W);

        // ---- Lane mux: random tests in both modes ------------------------------
        for (r = 0; r < 1000; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1) vector_b[j*W +: W] = $random(seed);
            scalar_b   = $random(seed);
            use_scalar = r[0];
            #1;
            if (use_scalar) check(lane_b, {LANES{scalar_b}}, "mux broadcast");
            else            check(lane_b, vector_b,          "mux vector");
        end

        // ---- Combiner: extreme values ------------------------------------------------
        lanes_in = {LANES{16'h7FFF}};  check_combiner;   // largest:  LANES * 32767
        lanes_in = {LANES{16'h8000}};  check_combiner;   // smallest: LANES * -32768
        lanes_in = {LANES{16'hFFFF}};  check_combiner;   // all -1
        lanes_in = {LANES*W{1'b0}};    check_combiner;   // all 0

        // ---- Combiner: random values -------------------------------------------------
        for (r = 0; r < 5000; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1) lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        $display("tb_lane_combiner: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule
