// CLAUSE: enum name range
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef enum int {A[3]=7} E; E value;
initial begin
value=A0; if(A1!=8 || A2!=9 || value.num()!=3 || value.name()!="A0") $fatal;
$display("PASS"); $finish;
end
endmodule
