// CLAUSE: Automatic function with a typed formal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
function automatic int f(input int x);return x+1;endfunction
initial begin if(f(6)!=7)$fatal(1,"result"); $display("PASS");end
endmodule
