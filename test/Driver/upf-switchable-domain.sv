// REQUIRES: upf
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --mlir-verify-each --native-scheduler=generic %s -o %t.o0
// RUN: %t.o0 | FileCheck %s --check-prefix=CHECK
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O3 --mlir-verify-each %s -o %t.o3
// RUN: %t.o3 | FileCheck %s --check-prefix=CHECK
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --execution-tier=bytecode %s -o %t.bc
// RUN: %t.bc | FileCheck %s --check-prefix=CHECK

module upf_leaf(input logic clk, input logic d, output logic q);
  always @(posedge clk) begin
    $display("leaf activation");
    q <= #4 d;
  end
endmodule

module upf_test;
  logic clk = 0, d = 1, power_en = 1, iso = 0;
  wire q;
  upf_leaf dut(clk, d, q);
  initial begin
    #1 clk = 1;
    #5;
    if (q !== 1'b1) $fatal(1, "normal powered behavior failed");
    $display("normal q=%b", q);
    clk = 0; d = 0;
    #1 clk = 1; // Queues a write that would commit at time 11.
    #1 iso = 1; power_en = 0;
    #1;
    if (dut.q !== 1'bx || q !== 1'b0) $fatal(1, "corruption/isolation failed");
    $display("off internal=%b isolated=%b", dut.q, q);
    clk = 0; d = 1;
    #1 clk = 1; // Must produce neither the display nor an NBA while OFF.
    #1 power_en = 1;
    #1;
    if (dut.q !== 1'bx) $fatal(1, "stale delayed NBA survived power loss");
    iso = 0;
    #1;
    if (q !== 1'bx) $fatal(1, "power restoration resurrected state");
    $display("restored q=%b", q);
    clk = 0;
    #1 clk = 1;
    #1;
    if (q !== 1'bx) $fatal(1, "an OFF-domain activation scheduled an NBA");
    #4;
    if (q !== 1'b1) $fatal(1, "new clock did not update restored domain");
    $display("new clock q=%b", q);
    clk = 0; d = 0;
    #1 clk = 1;
    #5;
    if (q !== 1'b0) $fatal(1, "expected known zero before isolation test");
    iso = 1'bx;
    #1;
    if (q !== 1'bx) $fatal(1, "unknown isolation control must corrupt even equal data/clamp");
    $display("unknown isolation q=%b", q);
    $finish;
  end
endmodule

// CHECK: leaf activation
// CHECK-NEXT: normal q=1
// CHECK-NEXT: leaf activation
// CHECK-NEXT: off internal=x isolated=0
// CHECK-NEXT: restored q=x
// CHECK-NEXT: leaf activation
// CHECK-NEXT: new clock q=1
// CHECK-NEXT: leaf activation
// CHECK-NEXT: unknown isolation q=x
