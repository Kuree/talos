// CLAUSE: checker execution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 3.6: the checker assertion is evaluated on every tick, passing and failing with the sampled value.
// CHECK: CHK pass v=1
// CHECK: CHK fail v=0
// CHECK: CHK pass v=1

checker check_v(event clock_event, logic value);
  a: assert property (@clock_event value) $display("CHK pass v=%0d", value); else $display("CHK fail v=%0d", value);
endchecker
module top;
  bit clk, v;
  check_v c(posedge clk, v);
  initial begin
    v = 1; #1 clk = 1; #1 clk = 0;
    v = 0; #1 clk = 1; #1 clk = 0;
    v = 1; #1 clk = 1; #1 clk = 0;
  end
endmodule
