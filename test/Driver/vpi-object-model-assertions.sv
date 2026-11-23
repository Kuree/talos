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

// Today: let, clocking io decls, property and sequence instances, property
// specs and the multiclock sequence are not reachable; the 5 concurrent
// directives also appear as vpiAlways (2 real), and the 8 assertion labels as
// vpiNamedBegin, which 9.3.5 does not create (IEEE 1800-2023 37.48-37.57).

// IEEE 1800-2023 37.48-37.57: clocking blocks, immediate and concurrent
// assertions, property and sequence declarations, multiclock sequences, let.
// Talos currently runs multiclock handoff only for a directive without
// disable iff, so this one lives outside top's default disable iff.
module multiclock(input logic clk, clk2, a, b);
  multi: assert property (@(posedge clk) a ##1 @(posedge clk2) b);
endmodule

module top;
  logic clk = 0, clk2 = 0, a = 1, b = 1, rst = 0;
  // Clocks change only at even times, so the odd-time audit has its own slot.
  always #2 clk = ~clk;
  always #4 clk2 = ~clk2;

  default clocking cb @(posedge clk);
    default input #1 output #2;
    input a;
    output b;
  endclocking

  default disable iff (rst);

  let both(x, y) = x && y;

  sequence s(x, y);
    int v;
    (x, v = 1) ##1 (y && v == 1);
  endsequence

  property p(x, y);
    @(posedge clk) x |-> ##1 y;
  endproperty

  checked_p: assert property (p(a, b)) else $error("failed");
  inferred: assert property (a |=> b);
  assumed: assume property (@(posedge clk) a);
  covered_s: cover sequence (@(posedge clk) s(a, b));
  multiclock mc(.clk(clk), .clk2(clk2), .a(a), .b(b));

  import "DPI-C" context function void vpi_object_model_audit();
  initial begin
    simple: assert (both(a, b));
    deferred: assume #0 (a);
    final_c: cover final (b);
    #9 vpi_object_model_audit();
    $finish;
  end
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiAlways objects=7 properties=6/6 relations=4/5 answers=70
// CHECK-NEXT: vpiAssignment objects=2 properties=7/8 relations=3/8 answers=20
// CHECK-NEXT: vpiBegin objects=1 properties=5/7 relations=3/21 answers=8
// CHECK-NEXT: vpiConstant objects=20 properties=7/10 relations=0/5 answers=140
// CHECK-NEXT: vpiDelayControl objects=3 properties=5/6 relations=2/5 answers=21
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=1 properties=17/19 relations=2/26 answers=19
// CHECK-NEXT: vpiInitial objects=1 properties=5/5 relations=4/5 answers=9
// CHECK-NEXT: vpiIODecl objects=4 properties=11/11 relations=4/10 answers=60
// CHECK-NEXT: vpiModule objects=2 properties=21/27 relations=15/51 answers=62
// CHECK-NEXT: vpiNamedBegin objects=8 properties=7/7 relations=3/21 answers=75
// CHECK-NEXT: vpiNullStmt objects=3 properties=5/6 relations=1/3 answers=18
// CHECK-NEXT: vpiOperation objects=2 properties=7/11 relations=4/7 answers=22
// CHECK-NEXT: vpiPort objects=4 properties=12/14 relations=5/7 answers=68
// CHECK-NEXT: vpiReg objects=10 properties=21/24 relations=8/24 answers=277
// CHECK-NEXT: vpiSysTaskCall objects=1 properties=7/9 relations=1/6 answers=8
// CHECK-NEXT: vpiTimeQueue objects=3 properties=3/3 relations=0/1 answers=9
// CHECK-NEXT: vpiPackage objects=1 properties=18/23 relations=0/27 answers=18
// CHECK-NEXT: vpiLogicTypespec objects=19 properties=6/7 relations=1/6 answers=129
// CHECK-NEXT: vpiClockingBlock objects=1 properties=7/9 relations=3/26 answers=10
// CHECK-NEXT: vpiPropertyDecl objects=1 properties=7/7 relations=1/5 answers=8
// CHECK-NEXT: vpiSequenceDecl objects=1 properties=7/7 relations=1/5 answers=8
// CHECK-NEXT: vpiImmediateAssert objects=1 properties=5/12 relations=2/8 answers=7
// CHECK-NEXT: vpiAssert objects=3 properties=7/12 relations=1/8 answers=24
// CHECK-NEXT: vpiAssume objects=1 properties=7/12 relations=1/7 answers=8
// CHECK-NEXT: vpiCover objects=1 properties=7/13 relations=1/7 answers=8
// CHECK-NEXT: vpiImmediateAssume objects=1 properties=5/12 relations=2/8 answers=7
// CHECK-NEXT: vpiImmediateCover objects=1 properties=5/12 relations=2/7 answers=7
// CHECK-NEXT: audit end
