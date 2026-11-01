// CLAUSE: upf_get_handle_by_name
// REQUIRES: upf
// XFAIL: *
// use of undeclared identifier 'upf_get_handle_by_name'
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.1.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;import UPF::*;
initial begin
if(upf_get_handle_by_name("/top")==0)$fatal(1,"scope handle");
$display("PASS");$finish;end endmodule
