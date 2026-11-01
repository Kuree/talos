// CLAUSE: p typename noevaluation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int calls; int signed value; string text; function automatic int bump(); calls++; return 7; endfunction
initial begin
text=$typename(bump()); if(calls!=0 || text!="int" || $typename(value)!="int") $fatal; $display("PRINT|value|%s|END",text);
$display("PASS"); $finish;
end
endmodule
