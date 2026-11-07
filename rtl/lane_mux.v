// =============================================================================
// lane_mux.v - chooses the second input (operand B) for every lane
// =============================================================================
// Each lane can take its second number from one of two places:
//
//   use_scalar = 0  ->  its own element of vector register vb
//                       VADD v3, v1, v2 : lane i computes v1[i] + v2[i]
//
//   use_scalar = 1  ->  one scalar value copied into every lane ("broadcast")
//                       VMUL v3, v1, s2 : lane i computes v1[i] * s2
//
// In hardware this is LANES small 2-to-1 switches (multiplexers), one per
// lane, all flipped by the same select signal.
// =============================================================================

module lane_mux #(
    parameter LANES = 8,
    parameter W     = 16
) (
    input  wire               use_scalar,  // 0 = vector, 1 = broadcast scalar
    input  wire [LANES*W-1:0] vector_b,    // operand B from a vector register
    input  wire [W-1:0]       scalar_b,    // operand B from a scalar register (low W bits)
    output wire [LANES*W-1:0] lane_b       // what each lane actually receives
);

    // {LANES{scalar_b}} glues LANES copies of scalar_b together,
    // so every lane slot holds the same number.
    wire [LANES*W-1:0] broadcast = {LANES{scalar_b}};

    assign lane_b = use_scalar ? broadcast : vector_b;

endmodule
