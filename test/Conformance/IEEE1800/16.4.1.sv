// CLAUSE: deferred observed
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit value=1; int actions;
function void success(); if(value!=0) $fatal(1,"early action"); actions++; endfunction
initial begin assert #0(value) success(); else $fatal(1,"wrong evaluated condition"); value=0;
#1; if(actions!=1) $fatal; $display("PASS"); $finish; end endmodule
