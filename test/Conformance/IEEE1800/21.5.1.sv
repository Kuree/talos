// CLAUSE: write packed memory
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=out.hex
// CHECK-DAG: {{^PASS$}}
// FILE0-DAG: {{^1234$}}

module top;
typedef struct packed{byte a,b;}T;T mem[1];
initial begin
mem[0]=16'h1234;$writememh("out.hex",mem);
$display("PASS");$finish;
end
endmodule
