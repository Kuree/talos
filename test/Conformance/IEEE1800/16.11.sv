// CLAUSE: Sequence endpoint invokes its attached function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit clk=0;
  int hits=0;
  function void bump(); hits++; endfunction
  a:assert property(@(posedge clk) (1,bump()));
  initial begin
    #1; clk=1; #1;
    if(hits!=1)$fatal(1,"match callback count=%0d",hits);
    $display("PASS");
  end
endmodule
