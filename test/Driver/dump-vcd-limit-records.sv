// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/lim.sim
// RUN: %t/lim.sim
// RUN: FileCheck %s < %t/lim.vcd

// IEEE 1800-2023 21.7.1.5: dumping stops once the file reaches its
// $dumplimit size, never inside a record. The limit (415 bytes, the header
// being 233) falls inside the third record of the slot at 45, a 32-bit value
// change formatted in place: the file keeps the slot's time and its first two
// records, then the limit comment.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  logic [31:0] b = 1;
  logic c = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) begin
    a <= a + 1;
    b <= b * 3 + 1;
    c <= ~c;
  end
  initial begin
    $dumpfile("lim.vcd");
    $dumplimit(415);
    $dumpvars(0, top);
    #100 $finish;
  end
endmodule

// CHECK: $enddefinitions $end
// CHECK: {{^}}#45{{$}}
// CHECK-NEXT: {{^}}1${{$}}
// CHECK-NEXT: {{^}}b101 !{{$}}
// CHECK-NEXT: {{^}}$comment dump limit of 415 bytes reached $end{{$}}
// CHECK-NOT: {{.}}
