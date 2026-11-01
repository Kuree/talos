// CLAUSE: p variable format
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string format,text,argument;
initial begin
format="[%0d][%s]"; argument="%h"; text=$sformatf(format,7,argument); if(text!="[7][%h]") $fatal(1,"text=%s",text); $sformat(text,format,8,argument); if(text!="[8][%h]") $fatal; $display("PRINT|value|%s|END",text);
$display("PASS"); $finish;
end
endmodule
