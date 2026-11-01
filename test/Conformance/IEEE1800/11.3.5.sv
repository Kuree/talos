// CLAUSE: short circuit
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int calls=0;bit value;function bit f();calls++;return 1;endfunction
initial begin
value=1'b1 || f();
if(!value || calls!=0)$fatal(1,"short circuit");
$display("PASS");$finish;
end
endmodule
