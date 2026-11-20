// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t
// RUN: %t | FileCheck %s
// RUN: talos -O3 --vpi=off --native-scheduler=eval -emit-llvm %s | FileCheck %s --check-prefix=IR
// RUN: talos -O3 --vpi=off --native-scheduler=eval -DORDERED_NBA %s -o %t.nba
// RUN: %t.nba | FileCheck %s
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic -DORDERED_NBA %s -o %t.queue
// RUN: %t.queue | FileCheck %s
//
// The two ends of this packed variable change in one blocking assignment.
// A computed disable must never see the words disagree (1800-2023 4.6,
// 9.4.2, 16.12). An actual disagreement between edges cancels the next
// attempt, including when the predicate clears before the following edge.
module wide_port(input logic [129:0] left, right, output logic [129:0] bus);
  always_comb bus = left ^ right;
endmodule
module top;
  bit clk, start;
  logic [129:0] left = '0, right = '0, bus;
  int failed, changes;
`ifdef ORDERED_NBA
  initial bus = '0;
  always @(left or right) bus <= left ^ right;
`else
  wide_port port(left, right, bus);
`endif
  always #5 clk = !clk;
  always @(bus) changes++;
  assert property (@(posedge clk) disable iff (bus[129] != bus[0]) start |=> 0)
    else failed++;
  initial begin
    #1 changes = 0;
    start = 1;
    #6 left = {1'b1, 128'b0, 1'b1};
    #1 start = 0;
    #12 start = 1;
    #7 right = 130'b1;
    #1 right = '0;
    #1 start = 0;
    #9 $display("failures=%0d changes=%0d bits=%b%b", failed, changes, bus[129], bus[0]);
    $finish;
  end
endmodule
// CHECK: failures=1 changes=3 bits=11
// IR: call void @talos_rt_v1_scheduler_wide_transition_owned
