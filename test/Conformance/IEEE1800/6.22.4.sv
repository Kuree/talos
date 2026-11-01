// CLAUSE: cast compatible
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef enum int{A=0}E;E e;
initial begin
e=E'(3);if(e!=3)$fatal(1,"cast conversion");
$display("PASS");$finish;
end
endmodule
