// CLAUSE: checker ff assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: OLD
// Clock inference for checker procedures, on the example of 17.5: p1a and p3a take
// the default clocking, p2a infers posedge clk1. Instances wait for the clock when
// it did not occur in the time step their process reached them, and p3a sees no
// default clock after its first instance.
// CHECK-DAG: 10 p1b
// CHECK-DAG: 10 p2a
// CHECK-DAG: 10 p2b
// CHECK-DAG: 20 p1b
// CHECK-COUNT-2: 30 p1a
// CHECK-COUNT-2: 50 p3b
// CHECK: {{^PASS$}}

checker clocking_example(logic sig1, sig2, default_clk, rst, event e1, e2, e3);
  bit l2, l3;
  default clocking @(posedge default_clk); endclocking
  always_ff @(e1) begin: p1_block
    p1a: assert property (sig1 == sig2) $display("%0t p1a", $time);
    p1b: assert property (@(e1) (sig1 == sig2)) $display("%0t p1b", $time);
  end
  always_ff @(e2 or e3) begin: p2_block
    l2 <= rst;
    p2a: assert property (sig1 == sig2) $display("%0t p2a", $time);
    p2b: assert property (@(e2) (sig1 == sig2)) $display("%0t p2b", $time);
  end
  always_ff @(rst or e3) begin: p3_block
    l3 <= rst;
    p3a: assert property (sig1 == sig2) $fatal(1, "p3a");
    p3b: assert property (@(e3) (sig1 == sig2)) $display("%0t p3b", $time);
  end
endchecker
module example;
  bit s1, s2, default_clk, rst, clk1, clk2;
  clocking_example c1(s1, s2, default_clk, rst, posedge clk1 or posedge clk2, posedge clk1, negedge rst);
  initial begin
    #10 clk1 = 1; #1 clk1 = 0;
    #9 clk2 = 1; #1 clk2 = 0;
    #9 default_clk = 1; #1 default_clk = 0;
    #9 rst = 1; #10 rst = 0;
  end
endmodule

checker c(input event clock);bit v=0;
always_ff @clock begin assert(!v)$display("OLD");else $fatal;v<=1;end
endchecker
module top;bit clk;c inst(posedge clk);example u();
initial begin #1;clk=1;#54;$display("PASS");$finish;end endmodule
