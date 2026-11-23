// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/shared.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/shared.sim 2> %t/diagnostics.txt
// RUN: FileCheck %s --check-prefix=TOP --check-prefix=VCD < %t/shared.vcd
// RUN: FileCheck %s --check-prefix=PORT --check-prefix=VCD < %t/shared.vcd
// RUN: FileCheck %s --check-prefix=DIAG < %t/diagnostics.txt

// IEEE 1800-2023 4.4.2.9, 21.7: a testbench that waits on data, not on the
// clock, keeps the periodic loop on the runtime's shared calendar, which
// drains runtime work after each edge and ends those slots in the drain. Its
// falling edges are silent (posedge-only consumers). At t=40 and t=60 runtime
// work is due at a silent fall: the slot ends once, after that work, so the
// fall merges into the slot's single record and into the $dumpall checkpoint
// (21.7.1.4), as the other tiers write them for this single-clock shape.
// The port copy d.din holds top.din at every slot end and shares its
// identifier code (21.7), as d.dout shares acc's (its continuous assignment);
// the clock port and top.dout also follow their respective sources.
module dut(input logic clk, input logic [7:0] din, output logic [7:0] dout);
  logic [7:0] acc = 0;
  always_ff @(posedge clk) acc <= acc + din;
  assign dout = acc;
endmodule

module top;
  logic clk = 0;
  logic [7:0] din = 1, dout;
  always #5 clk = ~clk;
  dut d(.clk(clk), .din(din), .dout(dout));
  initial begin
    $dumpfile("shared.vcd");
    $dumpvars(0, top);
    #1 repeat (3) begin @(dout); din <= din + 8'd3; end
    #15 din = 8'd2;
    #20 $dumpall;
    #13 $finish;
  end
endmodule

// Read the same expected histories through both sets of declarations. The
// destination can assign the port and its parent a common identifier.
// PORT: $scope module d $end
// PORT-NEXT: $var reg 8 [[DOUT:[^ ]+]] acc [7:0] $end
// PORT-NEXT: $var reg 1 [[CLK:[^ ]+]] clk $end
// PORT-NEXT: $var reg 8 [[DIN:[^ ]+]] din [7:0] $end
// PORT-NEXT: $var reg 8 [[DOUT]] dout [7:0] $end
// TOP: $scope module d $end
// TOP: $var reg 8 [[DIN:[^ ]+]] din [7:0] $end
// TOP: $upscope $end
// TOP-NEXT: $var reg 1 [[CLK:[^ ]+]] clk $end
// TOP-NEXT: $var reg 8 [[DIN]] din [7:0] $end
// TOP-NEXT: $var reg 8 [[DOUT:[^ ]+]] dout [7:0] $end
// VCD: $enddefinitions $end
// VCD: #0
// VCD-NEXT: $dumpvars
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b1 [[DIN]]
// VCD-DAG: b0 [[DOUT]]
// VCD: $end
// VCD: #5
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b100 [[DIN]]
// VCD-DAG: b1 [[DOUT]]
// VCD: #10
// VCD-DAG: 0[[CLK]]
// VCD: #15
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b111 [[DIN]]
// VCD-DAG: b101 [[DOUT]]
// VCD: #20
// VCD-DAG: 0[[CLK]]
// VCD: #25
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b1010 [[DIN]]
// VCD-DAG: b1100 [[DOUT]]
// VCD: #30
// VCD-DAG: 0[[CLK]]
// VCD: #35
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b10110 [[DOUT]]
// VCD: #40
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b10 [[DIN]]
// VCD: #45
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b11000 [[DOUT]]
// VCD: #50
// VCD-DAG: 0[[CLK]]
// VCD: #55
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b11010 [[DOUT]]
// VCD: #60
// VCD: $dumpall
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b10 [[DIN]]
// VCD-DAG: b11010 [[DOUT]]
// VCD: $end
// VCD: #65
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b11100 [[DOUT]]
// VCD: #70
// VCD-DAG: 0[[CLK]]
// VCD-NOT: #

// One preparation: the loop kept the clock for the whole run, draining the
// testbench in its own slots.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations=1 {{.*}}periodic_slot_drains=11{{$}}
