// CLAUSE: Derived sampled value functions finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// LSB and four-state rules from the clause. e is xx 01 01 10 0x 11 00, and the default past value is xx. Each function
// is beside its expansion; the future pair reports on the tick it reads.
// CHECK: ROSE=0100010 RE=0100010 FELL=0001001 FE=0001001 STABLE=1010000 SE=1010000 CHANGED=0101111 CE=0101111
// CHECK: GROSE=0100010 GRE=0100010 RISING=0100010 FALLING=0001001

module top;
  bit clk; logic [1:0] e; int t;
  logic [1:0] V[7] = '{2'bxx, 2'b01, 2'b01, 2'b10, 2'b0x, 2'b11, 2'b00};
  bit [0:6] ROSE, RE, FELL, FE, STABLE, SE, CHANGED, CE, GROSE, GRE, RISING, FALLING;
  global clocking @(posedge clk); endclocking
  cover property (@(posedge clk) $rose(e)) ROSE[t] = 1;
  cover property (@(posedge clk) $past(e[0]) !== 1 && e[0] === 1) RE[t] = 1;
  cover property (@(posedge clk) $fell(e)) FELL[t] = 1;
  cover property (@(posedge clk) $past(e[0]) !== 0 && e[0] === 0) FE[t] = 1;
  cover property (@(posedge clk) $stable(e)) STABLE[t] = 1;
  cover property (@(posedge clk) $past(e) === e) SE[t] = 1;
  cover property (@(posedge clk) $changed(e)) CHANGED[t] = 1;
  cover property (@(posedge clk) $past(e) !== e) CE[t] = 1;
  cover property (@($global_clock) $rose_gclk(e)) GROSE[t] = 1;
  cover property (@($global_clock) $past_gclk(e[0]) !== 1 && e[0] === 1) GRE[t] = 1;
  assert property (@($global_clock) $rising_gclk(e)) RISING[t] = 1; else ;
  assert property (@($global_clock) $falling_gclk(e)) FALLING[t] = 1; else ;
  initial begin
    for (t = 0; t < 7; t++) begin
      e = V[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("ROSE=%b RE=%b FELL=%b FE=%b STABLE=%b SE=%b CHANGED=%b CE=%b", ROSE, RE, FELL, FE, STABLE, SE, CHANGED, CE);
    $display("GROSE=%b GRE=%b RISING=%b FALLING=%b", GROSE, GRE, RISING, FALLING);
  end
endmodule
