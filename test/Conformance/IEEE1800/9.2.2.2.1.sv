// CLAUSE: always comb written exclusion
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  int a=0,b=0,prior=-1;
  always_comb begin prior=b; b=a; end
  initial begin
    #1; a=1; #1;
    if(b!=1 || prior!=0) $fatal(1,"self retrigger b=%0d prior=%0d",b,prior);
    $display("PASS"); $finish;
  end
endmodule
