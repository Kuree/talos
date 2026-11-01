// CLAUSE: procedural boolean control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// The clock is inferred from always @(posedge clk). The if guard selects attempts procedurally, the operand is
// sampled. A loop queues one instance per iteration with the automatic i. Under a differing procedure event, the
// matured instance waits for its next clock, so the first attempt is at tick 1.
// CHECK: P=0100 F=0010
// CHECK: LP=2110 LF=0112
// CHECK: NP=0100 NF=0011

module top;
  bit clk, en, a; bit [1:0] v; int t;
  bit [0:3] EN = 4'b0110, A = 4'b1100;
  bit [1:0] V[4] = '{2'b11, 2'b01, 2'b10, 2'b00};
  bit [0:3][3:0] P, F, LP, LF, NP, NF;
  always @(posedge clk) if (en) assert property (a) P[t]++; else F[t]++;
  always @(posedge clk) for (int i = 0; i < 2; i++) assert property (v[i]) LP[t]++; else LF[t]++;
  always @(negedge clk) assert property (@(posedge clk) a) NP[t]++; else NF[t]++;
  initial begin
    for (t = 0; t < 4; t++) begin
      en = EN[t]; a = A[t]; v = V[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P=%h F=%h", P, F);
    $display("LP=%h LF=%h", LP, LF);
    $display("NP=%h NF=%h", NP, NF);
  end
endmodule
