// CLAUSE: wait dynamic size
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 9.4.2 / Table 9-2: 0->1, 0->z and z->1 are posedges; 1->x, x->0 and 1->0 are negedges; edge and plain @x see all six changes.
// CHECK: pos=3 neg=3 edge=6 any=6

module top;
  logic x = 0;  int pe, ne, ee, ae;
  always @(posedge x) pe++;
  always @(negedge x) ne++;
  always @(edge x) ee++;
  always @(x) ae++;
  initial begin
    #1 x = 1;  #1 x = 1'bx;  #1 x = 0;  #1 x = 1'bz;  #1 x = 1;  #1 x = 0;  #1;
    $display("pos=%0d neg=%0d edge=%0d any=%0d", pe, ne, ee, ae);
  end
endmodule
