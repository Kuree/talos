// CLAUSE: Selecting a legacy VPI API still permits value access
// XFAIL: *
// NOTE: The supplied 2017 compatibility header has an invalid preprocessor condition.
// RUN: %clang -c -fPIC %S/Inputs/36.12.2/legacy.c -I%resource_dir/include -o %t.legacy.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full %s %t.legacy.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int value=7;import "DPI-C" context function int read_legacy();
initial begin
if(read_legacy()!=7)$fatal(1,"legacy VPI value");
$display("PASS");$finish;
end
endmodule
