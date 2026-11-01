// CLAUSE: lexical scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value=1;function int f();return value;endfunction
initial begin
begin int value=2;if(f()!=1)$fatal;end
$display("PASS");$finish;
end
endmodule
