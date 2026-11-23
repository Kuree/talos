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

// Today: module paths, path terms, timing checks and the specparam are not
// reachable, and the 4 timing checks appear as vpiAlways processes (2 real)
// instead of vpiTchk (IEEE 1800-2023 37.39-37.40).

// IEEE 1800-2023 37.39-37.40, 37.45: module paths, path terms and timing
// checks.
module cell_m(input a, b, en, clk, d, output y, z, q);
  logic notifier;
  reg r;
  assign y = a;
  assign z = b;
  always @(posedge clk) r <= d;
  assign q = r;
  specify
    specparam tpd = 3;
    (a +=> y) = (tpd, 4);
    if (en) (b *> z) = 2;
    (posedge clk *> (q : d)) = 6;
    $setup(d, posedge clk, 3, notifier);
    $hold(posedge clk, d &&& en, 4);
    $width(posedge clk, 2);
    $period(posedge clk, 10);
  endspecify
endmodule

module top;
  logic a = 0, b = 0, en = 1, clk = 0, d = 0;
  wire y, z, q;
  cell_m u(a, b, en, clk, d, y, z, q);
  always #10 clk = ~clk;
  import "DPI-C" context function void vpi_object_model_audit();
  initial begin
    #25 vpi_object_model_audit();
    $finish;
  end
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiAlways objects=6 properties=6/6 relations=4/5 answers=56
// CHECK-NEXT: vpiAssignment objects=2 properties=7/8 relations=3/8 answers=20
// CHECK-NEXT: vpiBegin objects=1 properties=5/7 relations=3/21 answers=8
// CHECK-NEXT: vpiConstant objects=44 properties=7/10 relations=0/5 answers=308
// CHECK-NEXT: vpiContAssign objects=3 properties=8/8 relations=4/6 answers=36
// CHECK-NEXT: vpiDelayControl objects=2 properties=5/6 relations=2/5 answers=14
// CHECK-NEXT: vpiEventControl objects=1 properties=5/6 relations=3/5 answers=8
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=1 properties=17/19 relations=2/26 answers=19
// CHECK-NEXT: vpiInitial objects=1 properties=5/5 relations=4/5 answers=9
// CHECK-NEXT: vpiIODecl objects=8 properties=11/11 relations=4/10 answers=120
// CHECK-NEXT: vpiModule objects=2 properties=21/27 relations=12/51 answers=58
// CHECK-NEXT: vpiNet objects=11 properties=25/28 relations=11/22 answers=351
// CHECK-NEXT: vpiOperation objects=2 properties=7/11 relations=4/7 answers=19
// CHECK-NEXT: vpiPort objects=8 properties=12/14 relations=5/7 answers=136
// CHECK-NEXT: vpiReg objects=11 properties=21/24 relations=9/24 answers=305
// CHECK-NEXT: vpiSysTaskCall objects=1 properties=7/9 relations=1/6 answers=8
// CHECK-NEXT: vpiTimeQueue objects=2 properties=3/3 relations=0/1 answers=6
// CHECK-NEXT: vpiPackage objects=1 properties=18/23 relations=0/27 answers=18
// CHECK-NEXT: vpiLogicTypespec objects=35 properties=6/7 relations=1/6 answers=243
// CHECK-NEXT: audit end
