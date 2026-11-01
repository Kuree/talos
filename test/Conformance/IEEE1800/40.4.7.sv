// CLAUSE: FSM pragmas work in one-line comments as they do in block comments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 4/6

module top;

  // 40.4.7: the same FSM in both forms, with two of three states reached in each.
  // tool state_vector line_cs enum L
  logic [1:0] line_cs = 0;
  parameter [1:0] // tool enum L
    L0 = 0, L1 = 1, L2 = 2;
  /* tool state_vector block_cs enum B */
  logic [1:0] block_cs = 0;
  parameter [1:0] /* tool enum B */
    B0 = 0, B1 = 1, B2 = 2;
  initial begin
    #1 line_cs = L1; #1 block_cs = B1;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
