// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.native
// RUN: %t.native > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref
// RUN: %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.two
// RUN: %t.two > %t.two.out && FileCheck %s < %t.two.out

module top;
  bit clk;
  logic [512:0] q, first = '0, second = '0;
  int incoherent, pulses;
  always #1 clk = !clk;
  always @(posedge clk) begin
    q <= first;
    q <= second;
  end
  wire mismatch = q[1] ^ q[512];
  always @(posedge mismatch) incoherent++;
  always @(posedge q[65]) pulses++;
  initial begin
    #2;
    first[1] = 1;
    first[512] = 1;
    second = first;
    #2;
    first[65] = 1;
    // The second NBA must restore this word although it equals the value
    // before the first NBA (1800-2023 4.6(b), 9.4.2, 10.4.2).
    #2;
    if (q !== second || pulses != 1 || incoherent != 0)
      $fatal(1, "wide NBA pulse=%0d incoherent=%0d", pulses, incoherent);
    first[65] = 0;
    first[322:321] = 2'bzx;
    second = first;
    #2;
    if (q !== second || incoherent != 0) $fatal(1, "wide NBA X/Z");
    $display("wide NBA pulse=%0d incoherent=%0d", pulses, incoherent);
    $finish;
  end
endmodule
// CHECK: wide NBA pulse=1 incoherent=0
