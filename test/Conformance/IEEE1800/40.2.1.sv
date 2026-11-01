// CLAUSE: Statement, toggle, FSM and assertion coverage over a two-level hierarchy without enumerating instances
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --coverage %s -o %t.exe
// RUN: %t.exe
// CHECK: fsm module 2/3 hier 4/6
// CHECK: assertion module 1/1 hier 2/2
// CHECK: toggle covered=1
// CHECK: toggle sum=1
// CHECK: statement covered=1
// CHECK: statement sum=1

// 40.2.1 b) names the four minimum types, and d) requires subhierarchy queries. Each leaf has one assertion, a three-state
// FSM that reaches two states, and a bit. SV_COV_HIER at top must sum the two leaves with top's own items.
module leaf(input bit clk);
  /* tool state_vector cs enum F */
  logic [1:0] cs = 0;
  parameter /* tool enum F */ S0 = 0, S1 = 1, S2 = 2;
  bit t;
  a: assert property (@(posedge clk) 1'b1);
  always @(posedge clk) begin cs <= S1; t <= ~t; end
endmodule
module top;
  bit clk;
  leaf u1(clk), u2(clk);
  `define SHOW(NAME, TYPE) \
    $display("%s module %0d/%0d hier %0d/%0d", NAME, \
             $coverage_get(TYPE, `SV_COV_MODULE, u1), $coverage_get_max(TYPE, `SV_COV_MODULE, u1), \
             $coverage_get(TYPE, `SV_COV_HIER, top), $coverage_get_max(TYPE, `SV_COV_HIER, top))
  initial begin
    repeat (4) #1 clk = ~clk;
    #1;
    `SHOW("fsm", `SV_COV_FSM_STATE);
    `SHOW("assertion", `SV_COV_ASSERTION);
    $display("toggle covered=%0d", $coverage_get(`SV_COV_TOGGLE, `SV_COV_MODULE, u1) > 0);
    $display("toggle sum=%0d", $coverage_get(`SV_COV_TOGGLE, `SV_COV_HIER, top) >= 2 * $coverage_get(`SV_COV_TOGGLE, `SV_COV_MODULE, u1));
    $display("statement covered=%0d", $coverage_get(`SV_COV_STATEMENT, `SV_COV_MODULE, u1) > 0);
    $display("statement sum=%0d", $coverage_get_max(`SV_COV_STATEMENT, `SV_COV_HIER, top) > 2 * $coverage_get_max(`SV_COV_STATEMENT, `SV_COV_MODULE, u1));
    $finish;
  end
endmodule
