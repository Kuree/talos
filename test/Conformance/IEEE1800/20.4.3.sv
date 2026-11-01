// CLAUSE: timeformat realtime scaling
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;
string text;
initial begin
 #1.25;
 $timeformat(-9,2," ns",0); text=$sformatf("%t",$realtime);
 $display("NS|%s",text); if(text!="1.25 ns") $fatal;
 $timeformat(-12,0," ps",0); text=$sformatf("%t",$realtime);
 $display("PS|%s",text); if(text!="1250 ps") $fatal;
 $display("PASS"); $finish;
end
endmodule
