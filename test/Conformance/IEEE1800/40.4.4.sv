// CLAUSE: A next-state signal is identified, and only the current-state signal reaches states
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 2/3

module top;

  // 40.4.4: ns holds the next state. It visits S2, and cs never takes it, so S2 is not covered.
  logic [7:0] cs = 0;
  logic [7:0] /* tool enum E */ ns = 1;
  // tool state_vector cs enum E
  parameter /* tool enum E */ S0 = 0, S1 = 1, S2 = 2;
  initial begin
    #1 cs = ns; #1 ns = S2;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
