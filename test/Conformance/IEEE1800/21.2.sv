// CLAUSE: p display write arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: {{LOG\|10:20\|END}}

function automatic int unused(); return 0; endfunction
module top;
int calls; function automatic int tag(int n); calls++; return n; endfunction
initial begin
$write("LOG|"); $write("%0d:%0d",tag(10),tag(20)); $display("|END"); if(calls!=2) $fatal;
$display("PASS"); $finish;
end
endmodule
