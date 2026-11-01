// CLAUSE: A part-select holds the current state, and other bits of the vector do not
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 2/4

module top;

  // 40.4.2: word[5:4] is the state. The low bits walk through 1, 2 and 3 without leaving M0, so only M0 and M2 are reached.
  /* tool state_vector word[5:4] MODE enum M */
  bit [7:0] word;
  parameter /* tool enum M */ M0 = 0, M1 = 1, M2 = 2, M3 = 3;
  initial begin
    #1 word = 8'h01; #1 word = 8'h02; #1 word = 8'h03; #1 word = 8'h20;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
