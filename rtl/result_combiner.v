// =============================================================================
// result_combiner.v - turns the lane outputs into the final results
// =============================================================================
// After the lanes finish, their outputs are combined in two ways:
//
//   1. vector_result : the lane outputs kept side by side as one vector.
//                      This is written back to a vector register
//                      (VADD, VMUL, VMAX ...).
//
//   2. sum_result    : all lane outputs added together into ONE number.
//                      This goes to a scalar register (VDOT and the other
//                      reduce instructions). With the lanes multiplying,
//                      this gives a dot product in a single instruction:
//                      sum of a[i] * b[i].
//
// The adding is done as a tree instead of a long chain:
//
//      lane: 0   1   2   3   4   5   6   7
//             \ /     \ /     \ /     \ /      round 1: 4 additions
//              +       +       +       +
//                \   /           \   /         round 2: 2 additions
//                  +               +
//                     \         /              round 3: 1 addition
//                          +
//
// A chain of 8 numbers needs 7 adders one after another; the tree needs only
// 3 rounds (log2 of 8), so the result is ready sooner and the clock can run
// faster.
//
// Each element is treated as a signed number and widened to 32 bits before
// adding, so the total does not overflow.
// =============================================================================

module result_combiner #(
    parameter LANES = 8,              // must be a power of two (1, 2, 4, 8 ...)
    parameter W     = 16              // bits per element; below 32 (the sum is 32 bits)
) (
    input  wire [LANES*W-1:0] lane_results,   // outputs of all the lane ALUs
    output wire [LANES*W-1:0] vector_result,  // same lanes, as one vector
    output wire [31:0]        sum_result      // all lanes added together
);

    // 1. The vector result is just the lanes as they are.
    assign vector_result = lane_results;

    // 2. The sum, using the tree described above.
    //    "partial" holds LANES running totals of 32 bits each, side by side
    //    (total number i sits in bits [i*32 +: 32]). In round 1, total 0
    //    becomes lanes 0+1, total 2 becomes lanes 2+3, and so on. Each round
    //    halves the number of totals until only total 0 is left.
    reg [32*LANES-1:0] partial;
    integer i, step;

    always @(*) begin
        // Widen every lane to 32 bits, copying its sign bit into the new top bits.
        for (i = 0; i < LANES; i = i + 1)
            partial[i*32 +: 32] = {{(32-W){lane_results[i*W + W-1]}}, lane_results[i*W +: W]};

        // Add neighbours: step = 1, 2, 4 ... (distance between the pair).
        for (step = 1; step < LANES; step = step * 2)
            for (i = 0; i + step < LANES; i = i + 2 * step)
                partial[i*32 +: 32] = partial[i*32 +: 32] + partial[(i + step)*32 +: 32];
    end

    assign sum_result = partial[31:0];

endmodule
