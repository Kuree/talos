// CLAUSE: Nexttime checks the following clock tick
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit clk=0,value=0;
  int hits=0;
  a:assert property(@(posedge clk) nexttime value)hits++;
    else $fatal(1,"nexttime value");
  initial begin
    #1; clk=1; #1;
    if(hits!=0)$fatal(1,"early result");
    clk=0; value=1; #1; clk=1; #1;
    if(hits!=1)$fatal(1,"next-clock result");
    $display("PASS"); $finish;
  end
endmodule
