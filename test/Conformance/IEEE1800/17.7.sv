// CLAUSE: Checker variables hold static state updated by always_ff; nets in a checker are rejected
// XFAIL: native
// native tier aborts with "partial eval ownership failed after static NBA lowering"; bytecode prints the expected lines
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/17.7/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: member not allowed in checker declaration
// CHECK: 85 fail counter=0{{$}}
// CHECK-NEXT: final counter=2{{$}}

// 17.7: the clause's counter_model; the counter wraps to 0 on the ninth tick, at 85, the only tick that can fail.
checker counter_model(logic flag);
  bit [2:0] counter = '0;
  always_ff @$global_clock
    counter <= counter + 1'b1;
  assert property (@$global_clock counter == 0 |-> flag)
    else $display("%0t fail counter=%0d", $time, $sampled(counter));
  final $display("final counter=%0d", counter);
endchecker : counter_model
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0, flag = 1;
  always #5 clk = ~clk;
  global clocking @(posedge clk); endclocking
  counter_model check(flag);
  initial begin
    #36 flag = 0;            // only ticks with counter == 0 can now fail
    #60 $finish;
  end
endmodule
