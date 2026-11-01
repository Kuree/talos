// CLAUSE: boolean control
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.6/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// An expression evaluating to x, z or 0 is false; any other value is true, as in a procedural if.
// CHECK: P=011000 F=100111
// DIAG: increment and decrement expressions are not allowed

module top;
  bit clk; logic [1:0] v; int t;
  logic [1:0] V[6] = '{2'b00, 2'b01, 2'b10, 2'bxx, 2'bzz, 2'b0x};
  bit [0:5][3:0] P, F;
  assert property (@(posedge clk) v) P[t]++; else F[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      v = V[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P=%h F=%h", P, F);
  end
endmodule
