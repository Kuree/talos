// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/ports.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/ports.sim 2> %t/diagnostics.txt
// RUN: FileCheck %s --check-prefix=EVCD < %t/ports.evcd
// RUN: FileCheck %s --check-prefix=DIAG < %t/diagnostics.txt

// IEEE 1800-2023 21.7.3: an extended VCD file records port value changes per
// time slot, like VCD. The generated periodic loop keeps the clock while it
// is open and ends every slot, falling edges included, in the runtime's dump
// hook; the file is the one every other tier writes.
module dut(input logic clk, input logic [3:0] i, output logic [3:0] o);
  logic [3:0] r = 0;
  always_ff @(posedge clk) r <= r ^ i;
  assign o = r;
endmodule

module top;
  logic clk = 0;
  logic [3:0] i = 4'h3;
  logic [3:0] o;
  always #5 clk = ~clk;
  always_ff @(negedge clk) i <= i + 4'd1;
  dut d(.clk(clk), .i(i), .o(o));
  initial begin
    $dumpports(d, "ports.evcd");
    #42 $finish;
  end
endmodule

// EVCD: $var port 1 [[CLK:<[0-9]+]] clk $end
// EVCD-NEXT: $var port [3:0] [[I:<[0-9]+]] i $end
// EVCD-NEXT: $var port [3:0] [[O:<[0-9]+]] o $end
// EVCD: $enddefinitions $end
// EVCD-NEXT: #0
// EVCD-NEXT: $dumpports
// EVCD-NEXT: pD 6 0 [[CLK]]
// EVCD-NEXT: pDDUU 6600 0066 [[I]]
// EVCD-NEXT: pLLLL 6666 0000 [[O]]
// EVCD-NEXT: $end
// EVCD-NEXT: #5
// EVCD-NEXT: pU 0 6 [[CLK]]
// EVCD-NEXT: pLLHH 6600 0066 [[O]]
// EVCD-NEXT: #10
// EVCD-NEXT: pD 6 0 [[CLK]]
// EVCD-NEXT: pDUDD 6066 0600 [[I]]
// EVCD-NEXT: #15
// EVCD-NEXT: pU 0 6 [[CLK]]
// EVCD-NEXT: pLHHH 6000 0666 [[O]]
// EVCD-NEXT: #20
// EVCD-NEXT: pD 6 0 [[CLK]]
// EVCD-NEXT: pDUDU 6060 0606 [[I]]
// EVCD-NEXT: #25
// EVCD-NEXT: pU 0 6 [[CLK]]
// EVCD-NEXT: pLLHL 6606 0060 [[O]]
// EVCD-NEXT: #30
// EVCD-NEXT: pD 6 0 [[CLK]]
// EVCD-NEXT: pDUUD 6006 0660 [[I]]
// EVCD-NEXT: #35
// EVCD-NEXT: pU 0 6 [[CLK]]
// EVCD-NEXT: pLHLL 6066 0600 [[O]]
// EVCD-NEXT: #40
// EVCD-NEXT: pD 6 0 [[CLK]]
// EVCD-NEXT: pDUUU 6000 0666 [[I]]
// EVCD-NEXT: $vcdclose #42 $end

// The loop kept the clock for the whole run.
// DIAG: talos-signal-diagnostics {{.*}}periodic_preparations=1 
