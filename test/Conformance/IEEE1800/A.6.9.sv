// CLAUSE: Task calls and discarded function returns
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n;
function int f(); n++; return n; endfunction
task t(); void'(f()); endtask
initial begin t(); if(n!=1)$fatal; $display("PASS"); end
endmodule
