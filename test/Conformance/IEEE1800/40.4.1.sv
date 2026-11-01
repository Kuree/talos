// CLAUSE: state_vector identifies the current-state signal, with the enumeration in the pragma or the declaration
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage=fsm %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm 4/5

module top;

  // 40.4.1 gives both ways to name the enumeration. s1 reaches two of three states and s2 both of its two.
  /* tool state_vector s1 enum E1 */
  logic [1:0] s1 = 0;
  parameter /* tool enum E1 */ A = 0, B = 1, C = 2;
  /* tool state_vector s2 */
  logic [7:0] /* tool enum E2 */ s2 = 0;
  parameter /* tool enum E2 */ P = 0, Q = 5;
  initial begin
    #1 s1 = B; #1 s2 = Q;
    #1;
    $display("fsm %0d/%0d", $coverage_get(`SV_COV_FSM_STATE,`SV_COV_MODULE,top), $coverage_get_max(`SV_COV_FSM_STATE,`SV_COV_MODULE,top));
    $finish;
  end
endmodule
