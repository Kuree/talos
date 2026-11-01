// CLAUSE: unmatched path warning
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module delayed(input wire a,output wire y); timeunit 1ns; timeprecision 1ns;
assign y=a; specify(a=>y)=1; endspecify endmodule
module top; timeunit 1ns; timeprecision 1ns; logic a=0; wire y; delayed dut(a,y);
initial begin
$sdf_annotate("unmatched.sdf",dut);
#10; a=1; #0; if(y!==0)$fatal(1,"early SDF"); #2; if(y!==1)$fatal(1,"late SDF"); $display("PASS"); $finish; end endmodule
