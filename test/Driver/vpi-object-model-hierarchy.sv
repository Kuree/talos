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

// Today: for-generate scopes and their gen scope array, UDP definitions and
// ref objs are not reachable (IEEE 1800-2023 37.5, 37.15, 37.36, 37.85).

// IEEE 1800-2023 37.5-37.16, 37.35-37.36, 37.47, 37.85: instances, ports,
// nets, primitives and generate scopes.
package pkg;
  int pv = 1;
endpackage

interface bus #(parameter int W = 4) (input logic clk);
  logic [W-1:0] data;
  logic valid;
  modport source(output data, valid);
  modport sink(input data, valid);
endinterface

primitive u_and(output y, input a, b);
  table
    0 ? : 0;
    ? 0 : 0;
    1 1 : 1;
  endtable
endprimitive

module leaf #(parameter int N = 2) (input logic [N-1:0] a, output wire y,
                                    bus.sink port);
  assign y = &a;
endmodule

program prog(input logic clk);
  initial #10;
endprogram

module top;
  logic clk = 0;
  logic [1:0] a = 2'b11;
  wire y0, y1, y2, g, u;
  wire [3:0] w;
  wire [1:0] arr [2];
  tri1 pulled;
  bus #(.W(4)) b(clk);
  leaf #(.N(2)) l0(.a(a), .y(y0), .port(b.sink));
  leaf l1[1:0](.a(a), .y({y1, y2}), .port(b.sink));
  prog p(clk);
  and #(1, 2) gate0(g, a[0], a[1]);
  u_and udp0(u, a[0], a[1]);
  assign (strong0, pull1) #2 w = {a, a};
  assign arr[0] = a;
  for (genvar i = 0; i < 2; i++) begin : gen
    wire gw = a[i];
  end
  if (1) begin : cond
    int local_var = pkg::pv;
  end
  import "DPI-C" context function void vpi_object_model_audit();
  initial #3 vpi_object_model_audit();
endmodule

// CHECK: null objects=1 properties=3/5 relations=3/12 answers=6
// CHECK-NEXT: vpiConstant objects=100 properties=8/10 relations=3/5 answers=706
// CHECK-NEXT: vpiContAssign objects=7 properties=8/8 relations=4/6 answers=81
// CHECK-NEXT: vpiDelayControl objects=2 properties=5/6 relations=2/5 answers=14
// CHECK-NEXT: vpiFuncCall objects=1 properties=6/11 relations=2/8 answers=8
// CHECK-NEXT: vpiFunction objects=1 properties=17/19 relations=2/26 answers=19
// CHECK-NEXT: vpiGate objects=1 properties=14/14 relations=2/6 answers=16
// CHECK-NEXT: vpiInitial objects=2 properties=5/5 relations=4/5 answers=17
// CHECK-NEXT: vpiIODecl objects=9 properties=11/11 relations=7/10 answers=135
// CHECK-NEXT: vpiModule objects=4 properties=21/27 relations=22/51 answers=131
// CHECK-NEXT: vpiNet objects=12 properties=27/28 relations=12/22 answers=394
// CHECK-NEXT: vpiNetBit objects=4 properties=25/28 relations=5/19 answers=120
// CHECK-NEXT: vpiNullStmt objects=1 properties=5/6 relations=1/3 answers=6
// CHECK-NEXT: vpiOperation objects=3 properties=7/11 relations=4/7 answers=33
// CHECK-NEXT: vpiParamAssign objects=2 properties=6/6 relations=4/6 answers=20
// CHECK-NEXT: vpiParameter objects=4 properties=15/15 relations=4/12 answers=76
// CHECK-NEXT: vpiPort objects=8 properties=12/14 relations=6/7 answers=137
// CHECK-NEXT: vpiPortBit objects=6 properties=10/12 relations=2/2 answers=72
// CHECK-NEXT: vpiPrimTerm objects=6 properties=7/7 relations=2/4 answers=54
// CHECK-NEXT: vpiReg objects=9 properties=21/24 relations=11/24 answers=257
// CHECK-NEXT: vpiRegBit objects=12 properties=21/24 relations=8/20 answers=340
// CHECK-NEXT: vpiTimeQueue objects=2 properties=3/3 relations=0/1 answers=6
// CHECK-NEXT: vpiUdp objects=1 properties=10/14 relations=2/7 answers=12
// CHECK-NEXT: vpiModuleArray objects=1 properties=8/8 relations=6/8 answers=14
// CHECK-NEXT: vpiNetArray objects=1 properties=25/28 relations=3/20 answers=28
// CHECK-NEXT: vpiRange objects=15 properties=6/6 relations=2/2 answers=120
// CHECK-NEXT: vpiGenScope objects=1 properties=8/9 relations=3/38 answers=11
// CHECK-NEXT: vpiPackage objects=2 properties=18/23 relations=2/27 answers=38
// CHECK-NEXT: vpiInterface objects=1 properties=19/24 relations=8/44 answers=27
// CHECK-NEXT: vpiProgram objects=1 properties=19/24 relations=5/38 answers=24
// CHECK-NEXT: vpiModport objects=2 properties=6/6 relations=2/3 answers=16
// CHECK-NEXT: vpiIntVar objects=2 properties=21/24 relations=4/19 answers=49
// CHECK-NEXT: vpiIntTypespec objects=8 properties=5/6 relations=1/2 answers=43
// CHECK-NEXT: vpiLogicTypespec objects=61 properties=6/7 relations=5/6 answers=473
// CHECK-NEXT: vpiArrayTypespec objects=1 properties=6/7 relations=5/7 answers=11
// CHECK-NEXT: vpiInterfaceTypespec objects=2 properties=6/8 relations=1/4 answers=14
// CHECK-NEXT: audit end
