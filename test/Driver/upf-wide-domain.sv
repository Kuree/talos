// REQUIRES: upf
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --mlir-verify-each %s -o %t.o0
// RUN: %t.o0 | FileCheck %s
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O3 --mlir-verify-each %s -o %t.o3
// RUN: %t.o3 | FileCheck %s
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --execution-tier=bytecode %s -o %t.bc
// RUN: %t.bc | FileCheck %s
// IEEE 1801-2018 9.5.3/9.6.2/9.8: corruption, queued-update cancellation and
// isolation apply to every packed bit, including values spanning machine words.
module upf_leaf(input logic clk, input logic [64:0] d, output logic [0:4][0:12] q);
  bit [0:1][0:3] state_bits;
  always @(posedge clk) begin
    q <= #3 d;
    state_bits <= d[7:0];
  end
endmodule
module upf_test;
  logic clk = 0;
  logic [0:0] power_en = 1, iso = 0;
  logic [64:0] d = 65'h1_01234567_89abcdef;
  wire [0:4][0:12] q;
  upf_leaf dut(clk, d, q);
  initial begin
    #1 clk = 1;
    #4;
    if (q !== d) $fatal(1, "wide powered NBA failed");
    clk = 0; d = 65'h0_f1e2d3c4_b5a69788;
    #1 clk = 1;
    #1 iso = 1; power_en = 0;
    #1;
    if (dut.q !== 'x || q !== '0 || dut.state_bits !== '0)
      $fatal(1, "wide corruption/clamp or two-state default failed");
    power_en = 1;
    #3 iso = 0;
    #1;
    if (q !== 'x) $fatal(1, "wide pending NBA survived OFF/ON");
    clk = 0; d = 65'h1_fedcba98_76543210;
    #1 clk = 1;
    #4;
    if (q !== d) $fatal(1, "wide restored NBA failed");
    iso = 1'bx;
    #1;
    if (q !== 'x) $fatal(1, "wide unknown isolation failed");
    $display("wide domain and one-bit vector controls passed");
    $finish;
  end
endmodule
// CHECK: wide domain and one-bit vector controls passed
