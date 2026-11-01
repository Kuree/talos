// CLAUSE: A parameter pragma lists the possible states, with or without a bit width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 3/6

module top;

  // 40.4.6: u reaches 0 and 2 of its four states and also holds 7, which is not a state. v reaches one of its two.
  /* tool state_vector u enum E */
  logic [2:0] u = 0;
  parameter /* tool enum E */ S0 = 0, S1 = 1, S2 = 2, S3 = 3;
  /* tool state_vector v enum F */
  logic [2:0] v = 1;
  parameter [2:0] /* tool enum F */ T0 = 1, T1 = 2;
  initial begin
    #1 u = S2; #1 u = 7;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
