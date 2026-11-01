// CLAUSE: string field width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string text;
initial begin
text=$sformatf("[%5s][%2s]","ABC","ABC"); if(text!="[  ABC][ABC]") $fatal;
$display("PASS"); $finish;
end
endmodule
