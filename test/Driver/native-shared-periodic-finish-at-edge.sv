// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/finish.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/finish.sim > %t/out.txt 2>&1
// RUN: FileCheck %s < %t/out.txt

// IEEE 1800-2023 9.2.3, 20.2: $finish runs the final procedures and ends the
// simulation; nothing of the slot runs after them. The testbench waits on
// data, so the periodic loop shares the runtime calendar and takes the
// slot's NBA cut, where the runtime runs the testbench, before dispatching
// the clocked owner. When that cut runs the $finish at the t=135 clock edge,
// the generated coordinator stops: the edge's owner neither runs (no
// "edge t=135") nor commits its NBA after the final procedure.
module dut(input logic clk, input logic [7:0] din, output logic [7:0] dout);
  logic [7:0] acc = 0;
  always_ff @(posedge clk) begin
    acc <= acc + din;
    if ($time > 120)
      $display("edge t=%0t", $time);
  end
  assign dout = acc;
endmodule

module top;
  logic clk = 0;
  logic [7:0] din = 0;
  logic [7:0] dout;
  always #5 clk = ~clk;
  dut d(.clk(clk), .din(din), .dout(dout));
  initial begin
    repeat (12) begin
      @(posedge clk);
      din <= din + 8'd3;
    end
    #20 $display("pre-finish acc=%h t=%0t", d.acc, $time);
    $finish;
  end
  final $display("final dout=%h acc=%h t=%0t", dout, d.acc, $time);
endmodule

// CHECK: edge t=125
// CHECK: pre-finish acc=ea t=135
// CHECK: final dout=ea acc=ea t=135
// CHECK-NOT: edge t=
// CHECK: talos-signal-diagnostics {{.*}}periodic_slot_drains={{[1-9][0-9]*}}
