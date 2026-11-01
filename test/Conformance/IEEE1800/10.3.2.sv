// CLAUSE: net decl updates
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 10.3.2: continuous assignment to net, variable, part-select and concatenation targets follows the RHS.
// CHECK: A w=5a hi=5 lo=a pw=a5 v=a5
// CHECK: B w=3c hi=3 lo=c pw=c3 v=c3

module top;
  logic [7:0] src = 8'h5a;
  wire [7:0] w;  assign w = src;                       // net LHS
  wire [3:0] hi, lo;  assign {hi, lo} = src;           // concatenation LHS
  wire [7:0] pw;  assign pw[3:0] = src[7:4];  assign pw[7:4] = src[3:0];  // part-select LHS
  logic [7:0] v;  assign v = src ^ 8'hff;              // variable LHS
  initial begin
    #1; $display("A w=%h hi=%h lo=%h pw=%h v=%h", w, hi, lo, pw, v);
    src = 8'h3c; #1; $display("B w=%h hi=%h lo=%h pw=%h v=%h", w, hi, lo, pw, v);
  end
endmodule
