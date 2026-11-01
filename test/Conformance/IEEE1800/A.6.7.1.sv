// CLAUSE: Named-field assignment pattern
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
typedef struct packed{bit[2:0]n;}T;T t;
initial begin t='{n:5};if(t.n!=5)$fatal(1,"result"); $display("PASS");end
endmodule
