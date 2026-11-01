// CLAUSE: Programs
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

program stimulus(input bit clock,input int data);
initial begin @(posedge clock); if(data!=7) $fatal(1,"data=%0d",data); $display("PASS"); #1; end
endprogram
module top; bit clock=0; int data=0;
stimulus p(clock,data); always @(posedge clock) data<=7;
initial #1 clock=1;
endmodule
