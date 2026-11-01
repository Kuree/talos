// CLAUSE: Typespec: vpiTypespec gives a variable's named type, vpiTypedefAlias walks to the aliased typedef and stops at NULL, and built-in types have no name
// XFAIL: *
// vpiEnumConst on a typedef alias of an enum returns NULL, and vpiLeftRange of a named array typespec reads 0 while its vpiRange reads the declared bound (detail 9).
// RUN: %clang -c -fPIC %S/Inputs/37.25/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: c type=vpiEnumTypespec name=colors alias=primary_colors alias-type=vpiEnumTypespec alias-alias=null
// CHECK: enum red=0 yellow=1 blue=2
// CHECK: t type=vpiTimeTypespec name=my_time alias-type=vpiTimeTypespec
// CHECK: plain type=vpiIntTypespec name=null
// CHECK: s type=vpiStructTypespec name=pair a:vpiIntTypespec b:vpiRealTypespec
// CHECK: ar type=vpiArrayTypespec name=row left=2 right=0 elem=vpiIntTypespec
// CHECK: vec type=vpiLogicTypespec name=null left=5 right=2
// CHECK: typedefs=6

module top;
typedef enum bit [0:2] {red, yellow, blue} primary_colors;
typedef primary_colors colors;
typedef time my_time;
typedef struct { int a; real b; } pair;
typedef int row [2:0];
typedef logic [1:0] unused_type;
colors c;
my_time t;
int plain;
pair s;
row ar;
logic [5:2] vec;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
