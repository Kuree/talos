// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/shared.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/shared.sim 2> %t/diagnostics.txt
// RUN: FileCheck %s --check-prefix=VCD < %t/shared.vcd
// RUN: FileCheck %s --check-prefix=DIAG < %t/diagnostics.txt

// IEEE 1800-2023 4.4.2.9, 21.7: a testbench that waits on data, not on the
// clock, keeps the periodic loop on the runtime's shared calendar, which
// drains runtime work after each edge and ends those slots in the drain. Its
// falling edges are silent (posedge-only consumers). At t=40 and t=60 runtime
// work is due at a silent fall: the slot ends once, after that work, so the
// fall merges into the slot's single record and into the $dumpall checkpoint
// (21.7.1.4), as the other tiers write them for this single-clock shape.
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

// VCD: $scope module d $end
// VCD-NEXT: $var reg 8 [[ACC:[^ ]+]] acc [7:0] $end
// VCD-NEXT: $var reg 1 [[DCLK:[^ ]+]] clk $end
// VCD-NEXT: $var reg 8 [[DDIN:[^ ]+]] din [7:0] $end
// VCD-NEXT: $var reg 8 [[DDOUT:[^ ]+]] dout [7:0] $end
// VCD-NEXT: $upscope $end
// VCD-NEXT: $var reg 1 [[CLK:[^ ]+]] clk $end
// VCD-NEXT: $var reg 8 [[DIN:[^ ]+]] din [7:0] $end
// VCD-NEXT: $var reg 8 [[DOUT:[^ ]+]] dout [7:0] $end
// VCD: $enddefinitions $end
// VCD-NEXT: #0
// VCD-NEXT: $dumpvars
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: b1 [[DIN]]
// VCD-NEXT: b0 [[DOUT]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: b1 [[DDIN]]
// VCD-NEXT: b0 [[DDOUT]]
// VCD-NEXT: b0 [[ACC]]
// VCD-NEXT: $end
// VCD-NEXT: #5
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b100 [[DIN]]
// VCD-NEXT: b1 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b100 [[DDIN]]
// VCD-NEXT: b1 [[DDOUT]]
// VCD-NEXT: b1 [[ACC]]
// VCD-NEXT: #10
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: #15
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b111 [[DIN]]
// VCD-NEXT: b101 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b111 [[DDIN]]
// VCD-NEXT: b101 [[DDOUT]]
// VCD-NEXT: b101 [[ACC]]
// VCD-NEXT: #20
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: #25
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b1010 [[DIN]]
// VCD-NEXT: b1100 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b1010 [[DDIN]]
// VCD-NEXT: b1100 [[DDOUT]]
// VCD-NEXT: b1100 [[ACC]]
// VCD-NEXT: #30
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: #35
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b10110 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b10110 [[DDOUT]]
// VCD-NEXT: b10110 [[ACC]]
// VCD-NEXT: #40
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: b10 [[DIN]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: b10 [[DDIN]]
// VCD-NEXT: #45
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b11000 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b11000 [[DDOUT]]
// VCD-NEXT: b11000 [[ACC]]
// VCD-NEXT: #50
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: #55
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b11010 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b11010 [[DDOUT]]
// VCD-NEXT: b11010 [[ACC]]
// VCD-NEXT: #60
// VCD-NEXT: $dumpall
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: b10 [[DIN]]
// VCD-NEXT: b11010 [[DOUT]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NEXT: b10 [[DDIN]]
// VCD-NEXT: b11010 [[DDOUT]]
// VCD-NEXT: b11010 [[ACC]]
// VCD-NEXT: $end
// VCD-NEXT: #65
// VCD-NEXT: 1[[CLK]]
// VCD-NEXT: b11100 [[DOUT]]
// VCD-NEXT: 1[[DCLK]]
// VCD-NEXT: b11100 [[DDOUT]]
// VCD-NEXT: b11100 [[ACC]]
// VCD-NEXT: #70
// VCD-NEXT: 0[[CLK]]
// VCD-NEXT: 0[[DCLK]]
// VCD-NOT: #

// One preparation: the loop kept the clock for the whole run, draining the
// testbench in its own slots.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations=1 {{.*}}periodic_slot_drains=11{{$}}
