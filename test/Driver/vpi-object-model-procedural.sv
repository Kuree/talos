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

// Today: the object counts below reflect the runtime's current statement and
// call inventory (IEEE 1800-2023 37.60-37.79).

// IEEE 1800-2023 37.27, 37.41-37.44, 37.60-37.80: statements, timing controls,
// tasks, functions, calls, named blocks and named events.
module top;
  event go, done, ev_arr [2];
  int n, total;
  logic [3:0] v, src;
  bit generated;
  wire [3:0] w;

  function automatic int add(input int a, int b = 1);
    return a + b;
  endfunction

  task automatic bump(ref int target, input int by, output int seen);
    #1 target += by;
    seen = target;
  endtask

  import "DPI-C" context function void vpi_object_model_audit();

  initial begin : main_block
    int seen;
    n = add(2);
    bump(total, 3, seen);
    if (n > 1) total++; else total--;
    case (n)
      0: total = 0;
      1, 2: total = 1;
      default: total = 2;
    endcase
    casez (v) 4'b1???: total = 3; default: ; endcase
    for (int k = 0; k < 2; k++) begin
      if (k == 1) continue;
      total += k;
    end
    foreach (ev_arr[k]) total += k;
    while (total > 100) break;
    do total++; while (total < 3);
    repeat (2) total++;
    v = repeat (2) @(go) src;
    fork : f
      forever #5 total++;
      begin #1 -> go; ->> done; end
    join_any
    disable f;
    fork #1 total++; join_none
    wait fork;
    wait (total > 0);
    wait_order (go, done);
    @(go or done) total++;
    #1 total = add(.a(1), .b(2));
    assign v = src;
    deassign v;
    force w = src;
    release w;
    // Audit in a time slot of its own, after the event generator stops.
    wait (generated);
    #1 vpi_object_model_audit();
    $finish;
  end

  // Enough ordered events for every wait in main_block, then stop.
  initial begin
    repeat (12) begin
      #1 -> go;
      #1 -> done;
    end
    generated = 1;
  end

  // A regressed wait or disable must fail the test rather than hang it.
  initial #1000 $fatal(1, "main_block did not finish");
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiAssignStmt objects=1 properties=5/6 relations=1/5 answers=6
// CHECK-NEXT: vpiAssignment objects=11 properties=7/8 relations=4/8 answers=104
// CHECK-NEXT: vpiBegin objects=5 properties=5/7 relations=3/21 answers=36
// CHECK-NEXT: vpiCase objects=2 properties=7/8 relations=3/5 answers=20
// CHECK-NEXT: vpiCaseItem objects=5 properties=5/5 relations=2/2 answers=31
// CHECK-NEXT: vpiConstant objects=45 properties=8/10 relations=3/5 answers=350
// CHECK-NEXT: vpiDeassign objects=1 properties=5/6 relations=1/4 answers=6
// CHECK-NEXT: vpiDelayControl objects=9 properties=5/6 relations=2/5 answers=61
// CHECK-NEXT: vpiDisable objects=1 properties=5/6 relations=1/4 answers=6
// CHECK-NEXT: vpiEventControl objects=2 properties=5/6 relations=2/5 answers=13
// CHECK-NEXT: vpiEventStmt objects=4 properties=5/7 relations=1/4 answers=24
// CHECK-NEXT: vpiFor objects=1 properties=6/8 relations=3/26 answers=9
// CHECK-NEXT: vpiForce objects=1 properties=5/6 relations=1/5 answers=6
// CHECK-NEXT: vpiForever objects=1 properties=5/6 relations=2/4 answers=7
// CHECK-NEXT: vpiFork objects=1 properties=5/8 relations=2/21 answers=7
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=2 properties=18/19 relations=5/26 answers=39
// CHECK-NEXT: vpiIf objects=1 properties=6/7 relations=3/5 answers=9
// CHECK-NEXT: vpiIfElse objects=1 properties=6/7 relations=2/6 answers=8
// CHECK-NEXT: vpiInitial objects=3 properties=5/5 relations=4/5 answers=27
// CHECK-NEXT: vpiModule objects=1 properties=21/27 relations=8/51 answers=29
// CHECK-NEXT: vpiNamedBegin objects=1 properties=7/7 relations=4/21 answers=11
// CHECK-NEXT: vpiNamedEvent objects=4 properties=12/12 relations=6/10 answers=68
// CHECK-NEXT: vpiNamedFork objects=1 properties=7/8 relations=2/21 answers=9
// CHECK-NEXT: vpiNet objects=1 properties=25/28 relations=6/22 answers=31
// CHECK-NEXT: vpiNetBit objects=4 properties=25/28 relations=5/19 answers=120
// CHECK-NEXT: vpiNullStmt objects=4 properties=5/6 relations=1/3 answers=24
// CHECK-NEXT: vpiOperation objects=6 properties=7/11 relations=4/7 answers=65
// CHECK-NEXT: vpiReg objects=2 properties=21/24 relations=9/24 answers=60
// CHECK-NEXT: vpiRegBit objects=8 properties=21/24 relations=8/20 answers=232
// CHECK-NEXT: vpiRelease objects=1 properties=5/6 relations=1/4 answers=6
// CHECK-NEXT: vpiRepeat objects=2 properties=5/6 relations=3/5 answers=15
// CHECK-NEXT: vpiRepeatControl objects=1 properties=5/5 relations=2/5 answers=7
// CHECK-NEXT: vpiSysTaskCall objects=2 properties=7/9 relations=1/6 answers=16
// CHECK-NEXT: vpiTask objects=1 properties=13/16 relations=4/22 answers=17
// CHECK-NEXT: vpiTaskCall objects=1 properties=7/8 relations=2/6 answers=9
// CHECK-NEXT: vpiTimeQueue objects=2 properties=3/3 relations=0/1 answers=6
// CHECK-NEXT: vpiWait objects=2 properties=5/6 relations=3/5 answers=16
// CHECK-NEXT: vpiWhile objects=1 properties=5/6 relations=3/5 answers=8
// CHECK-NEXT: vpiRange objects=5 properties=6/6 relations=2/2 answers=38
// CHECK-NEXT: vpiNamedEventArray objects=1 properties=10/10 relations=5/8 answers=15
// CHECK-NEXT: vpiPackage objects=1 properties=18/23 relations=0/27 answers=18
// CHECK-NEXT: vpiIntVar objects=10 properties=21/24 relations=5/19 answers=240
// CHECK-NEXT: vpiBitVar objects=1 properties=21/24 relations=7/23 answers=28
// CHECK-NEXT: vpiIntTypespec objects=23 properties=5/6 relations=1/2 answers=112
// CHECK-NEXT: vpiBitTypespec objects=6 properties=6/7 relations=1/6 answers=32
// CHECK-NEXT: vpiLogicTypespec objects=11 properties=6/7 relations=5/6 answers=89
// CHECK-NEXT: vpiArrayTypespec objects=1 properties=6/7 relations=5/7 answers=11
// CHECK-NEXT: vpiDoWhile objects=1 properties=5/6 relations=2/5 answers=7
// CHECK-NEXT: vpiOrderedWait objects=1 properties=5/6 relations=2/6 answers=7
// CHECK-NEXT: vpiWaitFork objects=1 properties=5/6 relations=1/3 answers=6
// CHECK-NEXT: vpiForeachStmt objects=1 properties=5/7 relations=2/14 answers=7
// CHECK-NEXT: vpiBreak objects=1 properties=5/6 relations=1/3 answers=6
// CHECK-NEXT: vpiContinue objects=1 properties=5/6 relations=1/3 answers=6
// CHECK-NEXT: vpiReturnStmt objects=1 properties=5/6 relations=2/4 answers=7
// CHECK-NEXT: vpiEventTypespec objects=5 properties=5/6 relations=1/2 answers=30
// CHECK-NEXT: audit end
