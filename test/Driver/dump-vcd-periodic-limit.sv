// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/limit.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/limit.sim > %t/out.txt 2>&1
// RUN: FileCheck %s --check-prefix=FIRST < %t/first.vcd
// RUN: FileCheck %s --check-prefix=SECOND < %t/second.vcd
// RUN: FileCheck %s --check-prefix=OUT < %t/out.txt

// IEEE 1800-2023 21.7.1.5: dumping stops once the file reaches its $dumplimit
// size. Inside the generated periodic loop the slot hook that closes the file
// also disarms the loop's end-of-slot hooks: the loop leaves once and runs on
// without them. A $dumpfile that replaces the closed file before its waveform
// started (21.7.1.1) rearms them for the pending selection.
module top;
  logic clk = 0;
  logic [7:0] cnt = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) cnt <= cnt + 1;
  initial begin
    $dumpfile("first.vcd");
    $dumplimit(0);
    $dumpvars(0, top);
    #12 $dumplimit(250);
    $dumpfile("second.vcd");
    #200 $display("cnt=%0d", cnt);
    $finish;
  end
endmodule

// FIRST: $comment dump limit of 0 bytes reached $end

// SECOND: $var reg 1 [[CLK:[^ ]+]] clk $end
// SECOND-NEXT: $var reg 8 [[CNT:[^ ]+]] cnt [7:0] $end
// SECOND: $enddefinitions $end
// SECOND-NEXT: #12
// SECOND-NEXT: $dumpvars
// SECOND-NEXT: 0[[CLK]]
// SECOND-NEXT: b1 [[CNT]]
// SECOND-NEXT: $end
// SECOND-NEXT: #15
// SECOND-NEXT: 1[[CLK]]
// SECOND-NEXT: b10 [[CNT]]
// SECOND-NEXT: #20
// SECOND-NEXT: 0[[CLK]]
// SECOND-NEXT: #25
// SECOND-NEXT: 1[[CLK]]
// SECOND-NEXT: b11 [[CNT]]
// Value and time records are written whole: the #30 time stamp that would
// pass the limit is dropped entirely, so the comment follows the last
// complete record.
// SECOND-NEXT: $comment dump limit of 250 bytes reached $end
// SECOND-NOT: #

// Prepared at time zero (the first file closed at once, so nothing armed),
// after the #12 runtime deadline, and once more after the second file's limit
// disarmed the hooks; the clock ran in the loop throughout.
// OUT: cnt=21
// OUT: talos-signal-diagnostics {{.*}}periodic_preparations=3 
