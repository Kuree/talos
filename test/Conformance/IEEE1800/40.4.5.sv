// CLAUSE: In one declaration, the first signal is the current state, the next is next state, others are neither
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 2/4

module top;

  // 40.4.5: "assumes nothing about signal nonstate". ns visits S2 and nonstate visits S3; only cs counts.
  /* tool state_vector cs */
  logic [1:0] /* tool enum myFSM */ cs = 0, ns = 0, nonstate = 0;
  parameter /* tool enum myFSM */ S0 = 0, S1 = 1, S2 = 2, S3 = 3;
  initial begin
    #1 cs = S1; #1 ns = S2; #1 nonstate = S3;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
