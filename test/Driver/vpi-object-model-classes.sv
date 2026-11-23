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

// Today: constraint items (implication, if-else, dist, solve-before, foreach)
// are not reachable, and the mailbox appears only as a class type
// (IEEE 1800-2023 37.33, 37.34, 37.38).

// IEEE 1800-2023 37.31-37.34, 37.38: class definitions, typespecs, objects,
// methods, constraints (expression, implication, if-else, dist, solve-before,
// foreach, soft) and mailboxes.
module top;
  virtual class Base #(parameter int W = 4);
    rand bit [W-1:0] value;
    local int secret;
    protected int shared;
    static int count;
    pure virtual function int width();
    static task tick();
      count++;
    endtask
  endclass

  class Derived extends Base #(8);
    rand int a, b;
    rand bit mode;
    rand int items [3];
    constraint plain_c { a > 0; a < 100; }
    constraint impl_c { mode -> b < 10; }
    constraint branch_c { if (mode) b > 1; else b > 20; }
    constraint dist_c { a dist { [1:10] := 1, [11:99] :/ 2 }; }
    constraint order_c { solve mode before b; }
    constraint each_c { foreach (items[k]) items[k] < 50; }
    constraint soft_c { soft b == 5; }
    function new();
      shared = 1;
    endfunction
    virtual function int width();
      return 8;
    endfunction
  endclass

  Derived d;
  mailbox #(int) mb;
  semaphore sem;
  import "DPI-C" context function void vpi_object_model_audit();

  initial begin
    d = new;
    void'(d.randomize());
    d.order_c.constraint_mode(0);
    mb = new;
    mb.put(d.width());
    sem = new(1);
    Base#(8)::tick();
    #1 vpi_object_model_audit();
  end
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiAssignment objects=4 properties=7/8 relations=3/8 answers=36
// CHECK-NEXT: vpiBegin objects=1 properties=5/7 relations=3/21 answers=8
// CHECK-NEXT: vpiConstant objects=25 properties=9/10 relations=3/5 answers=186
// CHECK-NEXT: vpiDelayControl objects=1 properties=5/6 relations=2/5 answers=7
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=9 properties=18/19 relations=5/26 answers=149
// CHECK-NEXT: vpiInitial objects=1 properties=5/5 relations=4/5 answers=9
// CHECK-NEXT: vpiModule objects=1 properties=21/27 relations=5/51 answers=26
// CHECK-NEXT: vpiParamAssign objects=1 properties=6/6 relations=3/6 answers=9
// CHECK-NEXT: vpiParameter objects=2 properties=15/15 relations=4/12 answers=34
// CHECK-NEXT: vpiRegBit objects=16 properties=21/24 relations=5/20 answers=408
// CHECK-NEXT: vpiTask objects=2 properties=13/16 relations=2/22 answers=30
// CHECK-NEXT: vpiTimeQueue objects=1 properties=3/3 relations=0/1 answers=3
// CHECK-NEXT: vpiRange objects=2 properties=6/6 relations=2/2 answers=16
// CHECK-NEXT: vpiRegArray objects=2 properties=25/26 relations=6/25 answers=61
// CHECK-NEXT: vpiPackage objects=2 properties=18/23 relations=3/27 answers=37
// CHECK-NEXT: vpiTypeParameter objects=2 properties=7/8 relations=3/6 answers=18
// CHECK-NEXT: vpiIntVar objects=19 properties=23/24 relations=4/19 answers=460
// CHECK-NEXT: vpiClassVar objects=3 properties=22/25 relations=7/21 answers=87
// CHECK-NEXT: vpiBitVar objects=4 properties=23/24 relations=6/23 answers=110
// CHECK-NEXT: vpiClassObj objects=3 properties=4/4 relations=9/14 answers=24
// CHECK-NEXT: vpiIntTypespec objects=18 properties=5/6 relations=1/2 answers=98
// CHECK-NEXT: vpiClassTypespec objects=5 properties=8/8 relations=13/24 answers=67
// CHECK-NEXT: vpiEnumTypespec objects=1 properties=5/6 relations=3/4 answers=8
// CHECK-NEXT: vpiEnumConst objects=5 properties=5/6 relations=1/1 answers=30
// CHECK-NEXT: vpiBitTypespec objects=4 properties=6/7 relations=5/6 answers=32
// CHECK-NEXT: vpiArrayTypespec objects=1 properties=6/7 relations=5/7 answers=11
// CHECK-NEXT: vpiMethodFuncCall objects=2 properties=6/11 relations=1/9 answers=14
// CHECK-NEXT: vpiMethodTaskCall objects=2 properties=7/9 relations=2/7 answers=17
// CHECK-NEXT: vpiClassDefn objects=3 properties=8/9 relations=12/25 answers=43
// CHECK-NEXT: vpiConstraint objects=21 properties=9/11 relations=1/3 answers=196
// CHECK-NEXT: vpiExtends objects=1 properties=5/5 relations=2/3 answers=7
// CHECK-NEXT: vpiReturnStmt objects=1 properties=5/6 relations=2/4 answers=7
// CHECK-NEXT: audit end
