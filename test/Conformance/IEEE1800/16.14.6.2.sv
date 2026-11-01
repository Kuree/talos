// CLAUSE: Disabling only queued assertion A removes A while leaving queued B to mature and pass at t
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
 bit clk=0; int passes=0,failures=0;
 initial begin
 a: assert property(@(posedge clk) 0) else failures++;
 b: assert property(@(posedge clk) 1) passes++;
 disable a;
 #2; if(passes!=1 || failures!=0) $fatal(1,"passes=%0d failures=%0d",passes,failures); $display("PASS"); $finish; end
 initial begin #1; clk=1; end
endmodule
