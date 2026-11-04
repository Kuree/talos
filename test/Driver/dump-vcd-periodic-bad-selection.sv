// RUN: rm -rf %t && mkdir -p %t && cd %t
// RUN: talos -O3 %s -o %t/bad.sim
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/bad.sim > %t/out.txt 2>&1
// RUN: FileCheck %s < %t/out.txt

// IEEE 1800-2023 21.7.1.2: $dumpvars names modules and variables. A selection
// that names neither writes no waveform; it is reported once and the run goes
// on, also when the generated periodic loop ends its slots in the dump hook:
// the failed plan closes the file, and the loop leaves once (a second
// preparation) to run on without hooks.
module top;
  logic clk = 0;
  logic [7:0] cnt = 0;
  string s = "hi";
  always #5 clk = ~clk;
  always_ff @(posedge clk) cnt <= cnt + 1;
  initial begin
    $dumpfile("bad.vcd");
    $dumpvars(0, top.s);
    #100 $display("cnt=%0d", cnt);
    $finish;
  end
endmodule

// CHECK: talos: $dumpvars selection 'top.s' does not name a design scope or variable; no waveform will be written
// CHECK-NOT: error
// CHECK: cnt=10
// CHECK: talos-signal-diagnostics {{.*}}periodic_preparations=2 
