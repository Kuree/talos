// CLAUSE: strong sequence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One clock tick, so every obligation is unmet at the end: strong operators require the clock to tick enough and
// fail, weak operators impose no such requirement. Nothing is reported before the trace ends.
// CHECK-NOT: failed
// CHECK: trace ended
// CHECK-DAG: strong failed
// CHECK-DAG: s_nexttime failed
// CHECK-DAG: s_always failed
// CHECK-DAG: s_eventually failed
// CHECK-DAG: s_until failed
// CHECK-DAG: s_until_with failed

module top;
  bit clk, a = 1, b = 0;
  assert property (@(posedge clk) weak(a ##1 b)) else $fatal(1, "weak");
  assert property (@(posedge clk) nexttime a) else $fatal(1, "nexttime");
  assert property (@(posedge clk) always [1:2] a) else $fatal(1, "always");
  assert property (@(posedge clk) eventually [1:2] b) else $fatal(1, "eventually");
  assert property (@(posedge clk) a until b) else $fatal(1, "until");
  assert property (@(posedge clk) a until_with b) else $fatal(1, "until_with");
  assert property (@(posedge clk) strong(a ##1 b)) else $display("strong failed");
  assert property (@(posedge clk) s_nexttime a) else $display("s_nexttime failed");
  assert property (@(posedge clk) s_always [1:2] a) else $display("s_always failed");
  assert property (@(posedge clk) s_eventually [1:2] b) else $display("s_eventually failed");
  assert property (@(posedge clk) a s_until b) else $display("s_until failed");
  assert property (@(posedge clk) a s_until_with b) else $display("s_until_with failed");
  initial begin
    #1 clk = 1;
    #1 clk = 0;
    $display("trace ended");
  end
endmodule
