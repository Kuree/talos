// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.four && %t.four | FileCheck %s
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.two && %t.two | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | FileCheck %s

module top;
  bit clk, pulse;
  logic en;
  logic [3:0] q = 0, source = 5;
  logic [3:0] lanes [3];
  wire [3:0] other = lanes[2];
  int rises;
  always #5 clk = !clk;
  always @(posedge q[0]) rises++;

  always_ff @(posedge clk) begin
    if (pulse) q <= 4'hf;
    // The hold still captures q if the earlier NBA will change it (4.6(b)).
    q <= en ? source : q;
    lanes[1] <= en ? source : lanes[1];
    // A load of a different element must still be staged on the false arm.
    lanes[2] <= en ? source : lanes[0];
  end
  assign lanes[0] = 4'ha;

  initial begin
    en = 1;
    #6;
    if (q !== 5 || lanes[1] !== 5 || other !== 5 || rises != 1) $fatal;
    source = 0;
    #10;
    if (q !== 0 || lanes[1] !== 0 || other !== 0) $fatal;
    en = 0;
    pulse = 1;
    #10;
    if (q !== 0 || lanes[1] !== 0 || other !== 10 || rises != 2) $fatal;
    pulse = 0;
    en = 1'bx;
    source = 4'b0110;
    #10;
    if ($isunknown(en)) begin
      if (q !== 4'b0xx0 || lanes[1] !== 4'b0xx0) $fatal;
    end else if (q !== 0 || lanes[1] !== 0)
      $fatal;
    $display("register hold and pending pulse passed");
    $finish;
  end
endmodule
// CHECK: register hold and pending pulse passed
