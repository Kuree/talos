// CLAUSE: module zero drive before renba
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.4.2.5: the property samples d in Preponed (0 at t=2, so it fails) and its action block runs later and reads the current d (1).
// CHECK: OBS fail t=2 d=1
// CHECK: OBS pass t=4 d=1

module top;
  bit clk, d;
  a1: assert property (@(posedge clk) d)
        $display("OBS pass t=%0t d=%0d", $time, d); else $display("OBS fail t=%0t d=%0d", $time, d);
  initial begin #1 d = 0; #1 clk = 1; d = 1; #1 clk = 0; #1 clk = 1; #1; end
endmodule
