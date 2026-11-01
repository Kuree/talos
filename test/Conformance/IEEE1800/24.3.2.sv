// CLAUSE: Program input observes the design NBA update
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

program P(input wire value);
  initial begin
    if(value!==1)$fatal(1,"program input=%b design=%b",value,top.value);
    $display("PASS");
  end
endprogram
module top;
  bit value=0;
  P p(value);
  initial value<=1;
endmodule
