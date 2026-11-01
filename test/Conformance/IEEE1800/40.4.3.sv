// CLAUSE: A concatenation holds the current state, in the order written
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 2/2

module top;

  // 40.4.3: {a, b} has a in the high bit. a=1, b=0 is 2'b10; the reversed order would be 2'b01, which is no state.
  /* tool state_vector {a, b} PAIR enum P */
  bit a, b;
  parameter /* tool enum P */ P0 = 2'b00, P2 = 2'b10;
  initial begin
    #1 a = 1;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
