// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 6.5: nets resolve multiple drivers (1 with z gives 1, 1 with 0 gives x) while a variable keeps its single driver / last procedural write.
// CHECK: A w=1 cv=1
// CHECK: B w=x
// CHECK: C w=0 cv=0
// CHECK: D v=1

module top;
  logic a = 1, v;  logic bz = 1'bz;  wire w;  logic cv;
  assign w = a;  assign w = bz;      // two drivers on a net are legal
  assign cv = a;                     // one continuous driver of a variable
  initial begin
    #1; $display("A w=%b cv=%b", w, cv);
    bz = 0; #1; $display("B w=%b", w);
    a = 0; #1; $display("C w=%b cv=%b", w, cv);
    v = 0; v = 1; $display("D v=%b", v);
  end
endmodule
