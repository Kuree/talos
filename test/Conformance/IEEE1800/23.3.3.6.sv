// CLAUSE: uwire port
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 23.3.3.6: a port joining a uwire to a wand net is not merged (Table 23-1) and must warn; the simulated values are still 1 on each side.
// DIAG: uwire
// CHECK: VALUES w=1 u=1

module cell_t (output uwire y); assign y = 1; endmodule
module top;
  wand w;  uwire u;
  cell_t d1(w);  cell_t d2(u);
  initial begin #1; $display("VALUES w=%b u=%b", w, u); end
endmodule
