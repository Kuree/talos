// CLAUSE: dynamic sdf filename
// XFAIL: *
// The frontend rejects legal empty optional SDF arguments.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top(input wire a,output wire y);assign y=a;specify(a=>y)=1;endspecify initial begin $sdf_annotate("delay.sdf",top,);$display("PASS");$finish;end endmodule
