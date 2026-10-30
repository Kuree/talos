// RUN: talos -O0 --vpi=off --native-scheduler=generic %s -o %t.o0
// RUN: %t.o0 | FileCheck %s
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.o3
// RUN: %t.o3 | FileCheck %s
// Both BP false-cycle patterns, including time-zero execution and recovery.
// CHECK: lanes sel=0 way=001 flag=0 copied=0
// CHECK-NEXT: lanes sel=1 way=111 flag=1 copied=1
// CHECK-NEXT: lanes sel=0 way=001 flag=0 copied=0
module native_false_cycle_lanes;
  logic [2:0] way;
  logic [1:0] lru = 2'b10;
  logic sel;
  always_comb sel = way[2];
  always_comb way[1] = lru[sel];

  logic [263:0] original, copied;
  logic flag;
  always_comb copied = original;
  always_comb flag = |copied[189 +: 5];
  always_comb original[263] = flag;

  task report;
    $display("lanes sel=%b way=%b flag=%b copied=%b", sel, way,
             flag, copied[263]);
  endtask
  initial begin
    way[2] = 0;
    way[0] = 1;
    original[262:0] = '0;
    #1; report();
    way[2] = 1;
    original[189 +: 5] = '1;
    #1; report();
    way[2] = 0;
    original[189 +: 5] = '0;
    #1; report();
    $finish;
  end
endmodule
