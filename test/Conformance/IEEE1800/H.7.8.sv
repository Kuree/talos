// CLAUSE: unpacked struct inout
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.7.8/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
typedef struct {int i;real r;} pair_t;import "DPI-C" function void c35_struct(inout pair_t v);pair_t v;
initial begin
v='{4,1.25};c35_struct(v);if(v.i!=11 || v.r!=2.5)$fatal(1,"struct ABI i=%d r=%f",v.i,v.r);
$display("PASS"); $finish;
end
endmodule
