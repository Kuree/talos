// CLAUSE: program reactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module dut;
  int x=0;
  initial x<=7;
endmodule
program observer;
  int y=0;
  initial begin
    if (top.d.x!=7) $fatal(1,"program before NBA: %0d",top.d.x);
    y<=9;
    #0;
    if(y!=0) $fatal(1,"Re-NBA before Re-Inactive: %0d",y);
    #1;
    if(y!=9) $fatal(1,"Re-NBA missing: %0d",y);
    $display("PASS");
  end
endprogram
module top; dut d(); observer p(); endmodule
