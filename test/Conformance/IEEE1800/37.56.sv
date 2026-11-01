// CLAUSE: Multiclock sequence expression: a multiclock sequence iterates its clocked sequences, each with its own clocking event and sequence
// XFAIL: *
// multiclock sequence expressions report expr=null and clocked count=0
// RUN: %clang -c -fPIC %S/Inputs/37.56/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: expr=vpiMulticlockSequenceExpr
// CHECK-NEXT: clocked=vpiClockedSeq event=posedge c1 seq=a
// CHECK-NEXT: clocked=vpiClockedSeq event=posedge c2 seq=b
// CHECK-NEXT: clocked count=2

module top;
  logic c1 = 0, c2 = 0, a = 1, b = 1;
  ma: assert property (@(posedge c1) a ##1 @(posedge c2) b);
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
