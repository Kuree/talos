// CLAUSE: Variables: vpiVariables lists each variable with its specific type, size and sign, a string's size follows its contents, and array members report vpiArrayMember and vpiIndex
// XFAIL: *
// vpi_get(vpiSigned) returns 0 for every variable, even int and logic signed, and vpi_handle(vpiExpr) returns NULL for a variable with an initializer (detail 8).
// RUN: %clang -c -fPIC %S/Inputs/37.17/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: var i type=vpiIntVar size=32 signed=1 value=-3
// CHECK-DAG: var l type=vpiReg size=8 signed=0 value=165
// CHECK-DAG: var si type=vpiShortIntVar size=16 signed=1 value=300
// CHECK-DAG: var b type=vpiBitVar size=3 signed=0 value=5
// CHECK-DAG: var e type=vpiEnumVar size=2 signed=0 value=2
// CHECK-DAG: var p type=vpiStructVar size=6 signed=0 value=27
// CHECK-DAG: var s type=vpiStringVar size=5 signed=0 value=hello
// CHECK-DAG: var r type=vpiRealVar value=2.5
// CHECK-DAG: var arr type=vpiRegArray size=4
// CHECK: variables=9
// CHECK: lifetime auto=0 alloc=1
// CHECK: init=-3
// CHECK: member full=top.arr[2] array-member=1 index=2 value=9 size=8
// CHECK: non-member array-member=0

module top;
int i = -3;
logic [7:0] l = 8'hA5;
shortint si = 300;
bit [2:0] b = 3'd5;
enum logic [1:0] {A, B, C} e = C;
struct packed { logic [1:0] hi; logic [3:0] lo; } p = '{1, 11};
string s = "ab";
real r = 2.5;
logic [7:0] arr [3:0];
import "DPI-C" context function void probe();
initial begin
  arr[2] = 8'd9;
  // Detail 9: a string's vpiSize is the number of characters it currently holds.
  s = "hello";
  probe();
  $finish;
end
endmodule
