// CLAUSE: An empty module instance provides a structural elaboration control for the empty checker i
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 23.2.4: the module items (continuous assign, gate, always, generate loop, initial) each contribute observable behaviour.
// CHECK: INIT r=4
// CHECK: A o=5 a=1 gen=101 cnt=0
// CHECK: B o=7 a=1 cnt=1

module items (output wire [3:0] o);
  logic [3:0] r = 4;  int cnt;  wire a;  wire [2:0] gen;
  assign o = r + 1;
  and g1 (a, r[2], 1'b1);
  always @(r) cnt++;
  for (genvar i = 0; i < 3; i++) begin : gb assign gen[i] = (i % 2 == 0); end
  initial #0.5 $display("INIT r=%0d", r);
endmodule
module top;
  wire [3:0] o;  items u(o);
  initial begin
    #1; $display("A o=%0d a=%b gen=%b cnt=%0d", o, u.a, u.gen, u.cnt);
    u.r = 6; #1; $display("B o=%0d a=%b cnt=%0d", o, u.a, u.cnt);
  end
endmodule
