// REQUIRES: upf
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --mlir-verify-each %s -o %t.o0
// RUN: %t.o0 | FileCheck %s
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O3 --mlir-verify-each %s -o %t.o3
// RUN: %t.o3 | FileCheck %s
// RUN: talos --upf-assume-powered-inputs --upf %S/Inputs/upf/switchable.upf -O0 --execution-tier=bytecode %s -o %t.bc
// RUN: %t.bc | FileCheck %s
// IEEE 1801-2018 9.5.3/9.6.7: each wait-loop shape must suppress complete
// activations while OFF and reevaluate on restoration without another edge.
module upf_leaf(input logic d, output logic [3:0] q = 0);
  always_comb q[0] = d;
  always @(*) q[1] = d;
  always @(d) q[2] = d;
  always_comb begin
    if (d) q[3] = 1'b1;
    else q[3] = 1'b0;
  end
endmodule
module upf_test;
  logic d = 1, power_en = 0, iso = 0;
  wire [3:0] q;
  upf_leaf dut(d, q);
  initial begin
    #1;
    if (dut.q !== 4'bxxxx) $fatal(1, "initial OFF must corrupt initialized state");
    power_en = 1;
    #1;
    if (q !== 4'b1111) $fatal(1, "power restoration must reevaluate combinational RTL");
    power_en = 0;
    #1 d = 0;
    #1;
    if (dut.q !== 4'bxxxx) $fatal(1, "combinational RTL evaluated while OFF");
    power_en = 1;
    #1;
    if (q !== 4'b0000) $fatal(1, "restoration failed without another data transition");
    $display("combinational power transitions passed");
    $finish;
  end
endmodule
// CHECK: combinational power transitions passed
