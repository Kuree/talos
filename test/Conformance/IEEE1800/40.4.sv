// CLAUSE: FSM pragmas override default extraction: the pragma's states define the FSM
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 2/2

module top;

  // 40.4: "The presence of any of these standard FSM description additions shall override the tool's default extraction".
  // The enum type has four labels and the pragma lists two states, so the FSM has two.
  typedef enum logic [1:0] {A, B, C, D} state_t;
  /* tool state_vector cs enum F */
  state_t cs = A;
  parameter /* tool enum F */ S0 = 0, S1 = 1;
  initial begin
    #1 cs = B; #1 cs = C; #1 cs = D;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
