// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/periodic.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/periodic.sim 2> %t/diagnostics.txt
// RUN: FileCheck %s --check-prefix=VCD < %t/periodic.vcd
// RUN: FileCheck %s --check-prefix=DIAG < %t/diagnostics.txt

// IEEE 1800-2023 21.7: an open value change dump records each time slot's
// changes at that slot's own time. The generated periodic loop keeps the
// clock while dumping and ends every slot it owns in the runtime's
// end-of-slot hook, including the silent falling edges it otherwise
// compresses away, so the waveform is the one every other tier writes
// (dump-vcd.sv) without returning the calendar to the runtime.
module top;
  logic clk = 0;
  logic [7:0] a = 0;
  logic [7:0] b;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + 8'd3;
  assign b = a ^ 8'h0f;
  initial begin
    $dumpfile("periodic.vcd");
    $dumpvars(0, top);
    #23 $dumpoff;
    #20 $dumpon;
    #20 $dumpall;
    #14 $finish;
  end
endmodule

// VCD: $var reg 8 [[A:[^ ]+]] a [7:0] $end
// VCD-NEXT: $var reg 8 [[B:[^ ]+]] b [7:0] $end
// VCD-NEXT: $var reg 1 [[CLK:[^ ]+]] clk $end
// VCD: $enddefinitions $end
// VCD-NEXT: #0
// VCD-NEXT: $dumpvars
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b0 [[A]]
// VCD-DAG: b1111 [[B]]
// VCD-NEXT: $end
// VCD-NEXT: #5
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b11 [[A]]
// VCD-DAG: b1100 [[B]]
// VCD-NEXT: #10
// VCD-DAG: 0[[CLK]]
// VCD-NEXT: #15
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b110 [[A]]
// VCD-DAG: b1001 [[B]]
// VCD-NEXT: #20
// VCD-DAG: 0[[CLK]]
// VCD-NEXT: #23
// VCD-NEXT: $dumpoff
// VCD-DAG: x[[CLK]]
// VCD-DAG: bx [[A]]
// VCD-DAG: bx [[B]]
// VCD-NEXT: $end
// VCD-NEXT: #43
// VCD-NEXT: $dumpon
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b1100 [[A]]
// VCD-DAG: b11 [[B]]
// VCD-NEXT: $end
// VCD-NEXT: #45
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b1111 [[A]]
// VCD-DAG: b0 [[B]]
// VCD-NEXT: #50
// VCD-DAG: 0[[CLK]]
// VCD-NEXT: #55
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b10010 [[A]]
// VCD-DAG: b11101 [[B]]
// VCD-NEXT: #60
// VCD-DAG: 0[[CLK]]
// VCD-NEXT: #63
// VCD-NEXT: $dumpall
// VCD-DAG: 0[[CLK]]
// VCD-DAG: b10010 [[A]]
// VCD-DAG: b11101 [[B]]
// VCD-NEXT: $end
// VCD-NEXT: #65
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b10101 [[A]]
// VCD-DAG: b11010 [[B]]
// VCD-NEXT: #70
// VCD-DAG: 0[[CLK]]
// VCD-NEXT: #75
// VCD-DAG: 1[[CLK]]
// VCD-DAG: b11000 [[A]]
// VCD-DAG: b10111 [[B]]
// VCD-NOT: #

// The loop kept the clock: it is prepared at time zero and again after each
// of the three runtime deadlines ($dumpoff, $dumpon, $dumpall) it hands back.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations=4 
