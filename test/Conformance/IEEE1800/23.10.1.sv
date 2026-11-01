// CLAUSE: defparam recalculates dependents
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module child; parameter int A=1,B=A+1; localparam int C=A+B; endmodule
module top; child u(); defparam u.A=7;
initial begin if(u.A!=7 || u.B!=8 || u.C!=15) $fatal; $display("PASS"); $finish; end
endmodule
