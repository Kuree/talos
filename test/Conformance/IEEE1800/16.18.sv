// CLAUSE: Assertion uses the clocking input sample
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit clk=0,data=0;
  int hits=0;
  always @(posedge clk) data<=1;
  clocking cb @(posedge clk); input #0 data; endclocking
  a:assert property(@(posedge clk) cb.data===1'b1)hits++;
    else $fatal(1,"clocking sample");
  initial begin
    #1; clk=1; #1;
    if(hits!=1)$fatal(1,"assertion count");
    $display("PASS");
  end
endmodule
