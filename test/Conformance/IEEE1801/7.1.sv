// CLAUSE: Consistent power-management cell definitions
// REQUIRES: upf
// XFAIL: *
// define_always_on_cell is unavailable, so conflicting cell definitions cannot be exercised.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/7.1/conflict.upf -O3 --execution-tier=%tier %s -o %t.reject.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: {{[Ee][Rr][Rr][Oo][Rr]}}

module aon(input a,output y,input var UPF::supply_net_type VDD,VDD2,SW,VSS);
assign y=a;
endmodule
module top;endmodule
