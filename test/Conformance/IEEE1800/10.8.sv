// CLAUSE: assignment context argument pattern
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {int a,b;} S; function int f(S v); return v.a*10+v.b; endfunction
initial begin
if(f('{a:2,b:3})!=23) $fatal;
$display("PASS"); $finish;
end
endmodule
