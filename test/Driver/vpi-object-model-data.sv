// RUN: %target_plugin_cxx -std=c++17 %target_pic -fno-exceptions -fno-rtti \
// RUN:   -c %S/Inputs/vpi-object-model-walker.cpp -I%resource_dir/include \
// RUN:   -I%source_root/include -I%obj_root/include -o %t.walker.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O0 %s %t.walker.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// One of the vpi-object-model-*.sv designs. The shared walker asks every
// property and relation the generated LRM model makes legal, on every object
// it reaches, and prints per kind how many legal queries answered on at least
// one object and how many (object, query) pairs answered. A legal query may
// rightly be empty in this design (an unnamed block has no name), so the lines
// below are an exact record of today's answers, including the known-wrong ones
// listed under "Today". Any changed line needs an explanation: a fixed gap or a
// regression. The executable's standard error lists every legal (kind, query)
// with its answer count and first VPI error; diff it before and after a change
// to see which query moved.

// Today: selects and operations inside expressions, defparam, specparam,
// param assigns and the real localparam are not reachable, and one
// assignment's lhs/rhs are empty (IEEE 1800-2023 37.19, 37.28, 37.58-37.59).

// IEEE 1800-2023 37.17-37.26, 37.28, 37.58-37.59: variables of every kind,
// typespecs, aggregates, fixed and dynamic arrays, queues, associative arrays,
// selects, and parameters.
module child;
  parameter int Q = 1;
endmodule

module top;
  typedef enum logic [1:0] {A, B, C} color_t;
  typedef color_t color_alias_t;
  typedef struct packed { logic [1:0] hi; logic [3:0] lo; } packed_t;
  typedef struct { int a; byte b; } unpacked_t;
  typedef union packed { logic [7:0] w; logic [7:0] u; } packed_union_t;
  typedef union tagged { int i; real r; } tagged_t;
  typedef int row_t [2:0];
  typedef time my_time_t;
  parameter int P = 4'b1010;
  localparam real R = 2.5;
  parameter type T = logic [3:0];
  int i = -3;
  shortint si = 300;
  longint li = 1;
  byte by = 8'h7f;
  integer ig = 5;
  bit [2:0] bv = 3'd5;
  logic [7:0] lv = 8'hA5;
  reg r1 = 1;
  real rv = 2.5;
  shortreal sr = 1.0;
  time tv = 10;
  realtime rt = 1.5;
  string s = "ab";
  chandle ch;
  color_t c = B;
  color_alias_t ca = C;
  packed_t p = '{1, 11};
  unpacked_t up = '{1, 2};
  packed_union_t un = 8'h42;
  tagged_t ta = tagged i 4;
  row_t rw;
  my_time_t mt;
  T typed;
  logic [7:0] mem [3:0];
  logic [1:0][3:0] pa;
  int dyn [];
  int q [$];
  int aa [string];
  logic [7:0] sel;
  child sub();
  defparam sub.Q = 12;
  specify
    specparam sp = 3;
  endspecify
  initial begin
    dyn = new[2];
    q.push_back(1);
    aa["k"] = 2;
    mem[1] = 8'h5;
    sel = lv[3:0] + lv[2] + lv[1 +: 2] + mem[1][2] + pa[1] + p.lo;
  end
  import "DPI-C" context function void vpi_object_model_audit();
  initial #1 vpi_object_model_audit();
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiAssignment objects=4 properties=7/8 relations=3/8 answers=36
// CHECK-NEXT: vpiBegin objects=1 properties=5/7 relations=3/21 answers=8
// CHECK-NEXT: vpiConstant objects=134 properties=8/10 relations=3/5 answers=940
// CHECK-NEXT: vpiDelayControl objects=1 properties=5/6 relations=2/5 answers=7
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=1 properties=17/19 relations=2/26 answers=19
// CHECK-NEXT: vpiInitial objects=2 properties=5/5 relations=4/5 answers=18
// CHECK-NEXT: vpiIntegerVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiModule objects=2 properties=21/27 relations=13/51 answers=56
// CHECK-NEXT: vpiParameter objects=2 properties=15/15 relations=4/12 answers=38
// CHECK-NEXT: vpiRealVar objects=3 properties=21/24 relations=5/19 answers=76
// CHECK-NEXT: vpiReg objects=15 properties=21/24 relations=12/24 answers=452
// CHECK-NEXT: vpiRegBit objects=85 properties=21/24 relations=8/20 answers=2388
// CHECK-NEXT: vpiTimeVar objects=2 properties=21/24 relations=4/19 answers=50
// CHECK-NEXT: vpiTimeQueue objects=1 properties=3/3 relations=0/1 answers=3
// CHECK-NEXT: vpiRange objects=23 properties=6/6 relations=2/2 answers=176
// CHECK-NEXT: vpiRegArray objects=5 properties=23/26 relations=10/25 answers=154
// CHECK-NEXT: vpiPackage objects=1 properties=18/23 relations=0/27 answers=18
// CHECK-NEXT: vpiTypeParameter objects=1 properties=8/8 relations=5/6 answers=13
// CHECK-NEXT: vpiLongIntVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiShortIntVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiIntVar objects=6 properties=21/24 relations=6/19 answers=158
// CHECK-NEXT: vpiShortRealVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiByteVar objects=2 properties=21/24 relations=5/19 answers=51
// CHECK-NEXT: vpiStringVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiEnumVar objects=2 properties=23/26 relations=6/23 answers=58
// CHECK-NEXT: vpiStructVar objects=2 properties=24/27 relations=7/25 answers=62
// CHECK-NEXT: vpiUnionVar objects=2 properties=24/27 relations=7/25 answers=62
// CHECK-NEXT: vpiBitVar objects=1 properties=21/24 relations=8/23 answers=29
// CHECK-NEXT: vpiChandleVar objects=1 properties=21/24 relations=4/19 answers=25
// CHECK-NEXT: vpiLongIntTypespec objects=1 properties=5/6 relations=1/2 answers=6
// CHECK-NEXT: vpiShortRealTypespec objects=1 properties=5/6 relations=1/2 answers=6
// CHECK-NEXT: vpiByteTypespec objects=3 properties=5/6 relations=1/2 answers=18
// CHECK-NEXT: vpiShortIntTypespec objects=1 properties=5/6 relations=1/2 answers=6
// CHECK-NEXT: vpiIntTypespec objects=13 properties=5/6 relations=1/2 answers=76
// CHECK-NEXT: vpiStringTypespec objects=2 properties=5/6 relations=1/2 answers=12
// CHECK-NEXT: vpiChandleTypespec objects=1 properties=5/6 relations=1/2 answers=6
// CHECK-NEXT: vpiEnumTypespec objects=2 properties=6/6 relations=4/4 answers=18
// CHECK-NEXT: vpiEnumConst objects=3 properties=6/6 relations=1/1 answers=21
// CHECK-NEXT: vpiIntegerTypespec objects=1 properties=5/6 relations=1/2 answers=6
// CHECK-NEXT: vpiTimeTypespec objects=3 properties=6/6 relations=2/2 answers=20
// CHECK-NEXT: vpiRealTypespec objects=4 properties=5/6 relations=1/2 answers=24
// CHECK-NEXT: vpiStructTypespec objects=2 properties=8/8 relations=2/3 answers=20
// CHECK-NEXT: vpiUnionTypespec objects=2 properties=8/8 relations=2/3 answers=20
// CHECK-NEXT: vpiBitTypespec objects=5 properties=6/7 relations=5/6 answers=39
// CHECK-NEXT: vpiLogicTypespec objects=36 properties=6/7 relations=5/6 answers=316
// CHECK-NEXT: vpiArrayTypespec objects=6 properties=7/7 relations=7/7 answers=63
// CHECK-NEXT: vpiTypespecMember objects=8 properties=7/7 relations=1/2 answers=64
// CHECK-NEXT: vpiMethodFuncCall objects=1 properties=6/11 relations=1/9 answers=7
// CHECK-NEXT: audit end
