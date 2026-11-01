// CLAUSE: SDF annotation of specparams
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module delay_cell(output logic q=0);timeunit 1ns;timeprecision 1ns;specparam T=1;initial #T q=1;endmodule
module top;timeunit 1ns;timeprecision 1ns;wire q;delay_cell dut(q);initial begin $sdf_annotate("delay.sdf",dut);#2;if(q!==0)$fatal(1,"specparam old value");#4;if(q!==1)$fatal(1,"specparam new value");$display("PASS");$finish;end endmodule
