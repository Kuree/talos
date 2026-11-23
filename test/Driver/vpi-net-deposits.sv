// RUN: %target_clang %target_pic -c %S/Inputs/vpi-net-deposits.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O0 %s %t.o -o %t.native.exe
// RUN: %t.native.exe | FileCheck %s --match-full-lines
// RUN: talos --std=1800-2023 --top=top --vpi=full -O0 \
// RUN:   --execution-tier=bytecode %s %t.o -o %t.bytecode.exe
// RUN: %t.bytecode.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 38.34: vpi_put_value on a net "overrides the resolved value
// of the net. This value shall remain in effect until one of the drivers of
// the net changes value. When this occurs, the net shall be re-evaluated using
// the normal resolution algorithms." The put reaches the net's readers and
// every port-connected name, a driver re-evaluated to its old value changes
// nothing, and a changed driver re-evaluates the whole net, including bits
// that another driver drives. A force overrides a put, and its release
// returns the drivers' value (10.6.2). A put is not a driver: from_child
// takes c.in + 1 once the child's assignment sees the put on w (ab), then
// holds a put on one of its bits (af). Native code and bytecode resolve nets
// on different paths, so both run. A net with a delay is refused.
module child(input wire [7:0] in, output wire [7:0] out);
  assign out = in + 8'd1;
endmodule

module top;
  logic clk = 0;
  logic [7:0] r = 8'h11;
  logic [3:0] lo = 4'h1, hi = 4'h2;
  logic [7:0] b0 = 8'h00, b1 = 8'hzz;
  wire [7:0] w = r;
  wire [7:0] reader = w;
  wire [7:0] masked = r & 8'h0f;
  wire [7:0] halves;
  assign halves[3:0] = lo;
  assign halves[7:4] = hi;
  wire [7:0] wired;
  assign wired = b0;
  assign wired = b1;
  wire [7:0] from_child;
  child c(.in(w), .out(from_child));
  wire #2 delayed;
  assign delayed = r[0];
  logic [7:0] q;
  always_ff @(posedge clk) q <= w;
  always #5 clk = ~clk;
  import "DPI-C" context function void put(input string name,
                                           input string value);
  import "DPI-C" context function void force_net(input string name,
                                                 input string value);
  import "DPI-C" context function void release_net(input string name);
  initial begin
    #1 put("top.w", "10101010");
    put("top.masked", "1x0z1x0z");
    put("top.halves", "10011001");
    put("top.wired", "00110011");
    put("top.delayed", "0");
    #0 $display("put: w=%h reader=%h c.in=%h from_child=%h masked=%b halves=%h wired=%h",
                w, reader, c.in, from_child, masked, halves, wired);
    put("top.from_child[2]", "1");
    #0 $display("bit put: from_child=%h", from_child);
    #20 $display("held: w=%h q=%h from_child=%h masked=%b halves=%h wired=%h",
                 w, q, from_child, masked, halves, wired);
    r = 8'h31;
    lo = 4'h5;
    b1 = 8'hff;
    #0 $display("drivers changed: w=%h reader=%h from_child=%h masked=%b halves=%h wired=%h",
                w, reader, from_child, masked, halves, wired);
    put("top.w", "01010101");
    force_net("top.w", "11110000");
    #1 $display("forced: w=%h", w);
    release_net("top.w");
    #1 $display("released: w=%h", w);
    $finish;
  end
endmodule

// CHECK: put top.delayed: writes to a net in a switch network, with a delay or with charge storage are not supported
// CHECK-NEXT: put: w=aa reader=aa c.in=aa from_child=ab masked=1x0z1x0z halves=99 wired=33
// CHECK-NEXT: bit put: from_child=af
// CHECK-NEXT: held: w=aa q=aa from_child=af masked=1x0z1x0z halves=99 wired=33
// CHECK-NEXT: drivers changed: w=31 reader=31 from_child=32 masked=1x0z1x0z halves=25 wired=xx
// CHECK-NEXT: forced: w=f0
// CHECK-NEXT: released: w=31
