// =============================================================================
// vec_regfile.v - the vector register file
// =============================================================================
// A small, very fast storage area inside the processor. It holds NREGS
// vector registers (v0 .. v7). Each register holds one whole vector:
// LANES elements of W bits, so 8 x 16 = 128 bits by default.
//
// Ports:
//   * two READ ports  (A and B) - an instruction like VADD v3, v1, v2 needs
//     to read two registers at the same time. Reading has no clock: the
//     data shows up as soon as the address is set.
//   * one WRITE port - the answer is saved on the rising clock edge, but
//     only when write_en is 1.
//
// If an instruction reads and writes the same register (VADD v1, v1, v2),
// it reads the OLD value, and the new value is saved at the clock edge.
// =============================================================================

module vec_regfile #(
    parameter LANES = 8,
    parameter W     = 16,
    parameter NREGS = 8               // number of vector registers
) (
    input  wire                     clk,

    // Read port A
    input  wire [$clog2(NREGS)-1:0] read_addr_a,
    output wire [LANES*W-1:0]       read_data_a,

    // Read port B
    input  wire [$clog2(NREGS)-1:0] read_addr_b,
    output wire [LANES*W-1:0]       read_data_b,

    // Write port
    input  wire                     write_en,
    input  wire [$clog2(NREGS)-1:0] write_addr,
    input  wire [LANES*W-1:0]       write_data
);

    // The storage itself: NREGS rows, each one vector wide.
    reg [LANES*W-1:0] regs [0:NREGS-1];

    // Start every register at zero so simulations never show unknown (X) values.
    integer i;
    initial begin
        for (i = 0; i < NREGS; i = i + 1)
            regs[i] = {LANES*W{1'b0}};
    end

    // Reading: just look up the row (no clock needed).
    assign read_data_a = regs[read_addr_a];
    assign read_data_b = regs[read_addr_b];

    // Writing: happens only on the rising edge of the clock.
    always @(posedge clk) begin
        if (write_en)
            regs[write_addr] <= write_data;
    end

endmodule
