// =============================================================================
// vec_alu_array.v - LANES lane ALUs working side by side
// =============================================================================
// This is where the parallel work happens. A vector of LANES elements is
// one long bus of LANES*W bits, with lane 0 in the lowest W bits:
//
//      bus bits:   [127 .. 112] ... [31 .. 16] [15 .. 0]
//      lane:            7       ...      1         0
//
// The generate loop below makes one vec_alu_lane per lane and wires each one
// to its own W-bit slice of the buses. All lanes share the same "op", so a
// single instruction makes all of them do the same job in the same clock cycle.
// =============================================================================

module vec_alu_array #(
    parameter LANES = 8,             // how many lanes (calculators) work in parallel
    parameter W     = 16             // bits per element
) (
    input  wire [3:0]         op,    // one job, shared by every lane
    input  wire [LANES*W-1:0] a,     // operand A, all lanes packed together
    input  wire [LANES*W-1:0] b,     // operand B, all lanes packed together
    output wire [LANES*W-1:0] y      // results, all lanes packed together
);

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : lane
            // a[i*W +: W] means "W bits starting at bit i*W", i.e. lane i.
            vec_alu_lane #(.W(W)) u_alu (
                .op (op),
                .a  (a[i*W +: W]),
                .b  (b[i*W +: W]),
                .y  (y[i*W +: W])
            );
        end
    endgenerate

endmodule
