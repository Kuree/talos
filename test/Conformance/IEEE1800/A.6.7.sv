// CLAUSE: Case item and default branch syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n;
initial begin case(2)1:n=4;2:n=7;default:n=9;endcase if(n!=7)$fatal(1,"result"); $display("PASS");end
endmodule
