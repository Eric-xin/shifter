// Exhaustive self-checking testbench for Shifter_8bit_sized.
// Applies all 256 inputs x 8 shift amounts (2048 vectors) and compares Y to a
// golden model. Use the same SHIFT_LEFT / ROTATE / FILL_ONE defines as the model.
//
//   +define+SETTLE=<ns>   time to wait after each input change (default 10)
`timescale 1ns/1ps
`ifndef SETTLE
  `define SETTLE 10
`endif

module tb_Shifter_8bit_sized;
    reg  [7:0] a;
    reg  [2:0] s;
    wire [7:0] y;
    supply1 VDD;
    supply0 VSS;

    Shifter_8bit_sized dut (
        .A0(a[0]), .A1(a[1]), .A2(a[2]), .A3(a[3]),
        .A4(a[4]), .A5(a[5]), .A6(a[6]), .A7(a[7]),
        .S0(s[0]), .S1(s[1]), .S2(s[2]),
        .Y0(y[0]), .Y1(y[1]), .Y2(y[2]), .Y3(y[3]),
        .Y4(y[4]), .Y5(y[5]), .Y6(y[6]), .Y7(y[7]),
        .VDD(VDD), .VSS(VSS)
    );

`ifdef FILL_ONE
    localparam [7:0] FILL = 8'hFF;
`else
    localparam [7:0] FILL = 8'h00;
`endif

    function [7:0] golden(input [7:0] x, input [2:0] n);
        begin
`ifdef ROTATE
  `ifdef SHIFT_LEFT
            golden = (x << n) | (x >> (8 - n));
  `else
            golden = (x >> n) | (x << (8 - n));
  `endif
`else
  `ifdef SHIFT_LEFT
            golden = {x, FILL} >> (8 - n);
  `else
            golden = {FILL, x} >> n;
  `endif
`endif
        end
    endfunction

    integer i, j, errors, checks;
    reg [7:0] exp;

    initial begin
        $dumpfile("tb_Shifter_8bit_sized.vcd");
        $dumpvars(0, tb_Shifter_8bit_sized);
        errors = 0; checks = 0;
        a = 0; s = 0;
        #(`SETTLE);

        for (j = 0; j < 8; j = j + 1) begin
            for (i = 0; i < 256; i = i + 1) begin
                a = i; s = j;
                #(`SETTLE);
                exp = golden(a, s);
                checks = checks + 1;
                if (y !== exp) begin
                    errors = errors + 1;
                    if (errors <= 20)
                        $display("FAIL t=%0t  A=%b S=%0d  Y=%b  expected=%b",
                                 $time, a, s, y, exp);
                end
            end
        end

        // A few readable spot checks
        $display("--- spot checks ---");
        a = 8'b1011_0110;
        for (j = 0; j < 8; j = j + 1) begin
            s = j; #(`SETTLE);
            $display("A=%b S=%0d -> Y=%b (exp %b) %s", a, s, y, golden(a, s),
                     (y === golden(a, s)) ? "ok" : "MISMATCH");
        end

        if (errors == 0)
            $display("PASS: %0d/%0d vectors correct", checks, checks);
        else
            $display("FAIL: %0d of %0d vectors wrong", errors, checks);
        $finish;
    end
endmodule
