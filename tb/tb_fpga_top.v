// =============================================================================
// tb_fpga_top.v - checks the board version (fpga_top) gives the right answer
// =============================================================================
// This is the design exactly as it goes onto the FPGA, memories included.
// Like a freshly programmed chip, nobody presses the reset button: the
// power-on reset inside fpga_top must start the program by itself.
//
// After HALT we compare, with what the golden model expects:
//   * the scalar register picked by +sel= and the 8 LEDs (+expect=, in hex)
//   * every word of the data memory (+expect_mem=, a hex file)
//
// syn/run_syn.py runs this for every lane count before synthesis, from a
// folder that holds program.hex and data.hex.
// =============================================================================

`timescale 1ns/1ps

module tb_fpga_top;

    parameter LANES = 8;
    localparam W      = 16;
    localparam DDEPTH = 1024;       // fpga_top's data memory (DADDR_W = 10)

    reg        clk = 1'b0;
    reg        rst = 1'b0;          // the button is never pressed
    reg  [2:0] sel = 3'd3;
    wire [7:0] led;
    wire       done;

    always #5 clk = ~clk;

    fpga_top #(.LANES(LANES)) dut (.clk(clk), .rst(rst), .sel(sel), .led(led), .done(done));

    reg [31:0]        expected;
    reg [LANES*W-1:0] expect_mem [0:DDEPTH-1];
    reg [8*256-1:0]   mem_file;
    integer           cycles, i, errors;

    initial begin
        if (!$value$plusargs("expect=%h", expected) ||
            !$value$plusargs("expect_mem=%s", mem_file)) begin
            $display("usage: +expect=<hex value of the selected register> +expect_mem=<file>");
            $display("TEST FAILED");
            $finish;
        end
        if (!$value$plusargs("sel=%d", sel)) sel = 3'd3;
        $readmemh(mem_file, expect_mem);

        cycles = 0;
        // done is unknown (X) until the power-on reset has run, so wait for a real 1.
        while (done !== 1'b1 && cycles < 20000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        #1;

        errors = 0;
        for (i = 0; i < DDEPTH; i = i + 1)
            if (dut.dmem[i] !== expect_mem[i]) begin
                errors = errors + 1;
                if (errors <= 5)
                    $display("  MEMORY MISMATCH word %0d: got %h want %h", i, dut.dmem[i], expect_mem[i]);
            end

        $display("board run: done=%b after %0d cycles, s%0d=%h (expected %h), LEDs=%h, %0d memory errors",
                 done, cycles, sel, dut.debug_data, expected, led, errors);
        if (done && dut.debug_data === expected && led === expected[7:0] && errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule
