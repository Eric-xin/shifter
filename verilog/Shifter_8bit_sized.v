// Behavioral reference model of Shifter_8bit_sized (8-bit, 3-stage log/barrel shifter).
// Port names match the Virtuoso symbol so the testbench can bind to either this
// model (Icarus/Verilator) or the netlisted schematic (Xcelium / Spectre AMS).
//
// Default behavior: logical RIGHT shift by S[2:0], zero fill.
// Override with: -DSHIFT_LEFT, -DROTATE, -DFILL_ONE
`timescale 1ns/1ps
module Shifter_8bit_sized (
    input  A0, A1, A2, A3, A4, A5, A6, A7,
    input  S0, S1, S2,
    output Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7,
    inout  VDD, VSS
);
    wire [7:0] a = {A7, A6, A5, A4, A3, A2, A1, A0};
    wire [2:0] s = {S2, S1, S0};
    reg  [7:0] y;

    always @* begin
`ifdef ROTATE
  `ifdef SHIFT_LEFT
        y = (a << s) | (a >> (8 - s));
  `else
        y = (a >> s) | (a << (8 - s));
  `endif
`else
  `ifdef SHIFT_LEFT
        y = {a, {8{`ifdef FILL_ONE 1'b1 `else 1'b0 `endif}}} >> (8 - s);
  `else
        y = {{8{`ifdef FILL_ONE 1'b1 `else 1'b0 `endif}}, a} >> s;
  `endif
`endif
    end

    assign {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0} = y;
endmodule
