// CLAUSE: enum declaration order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef enum {HIGH=9,LOW=2,MID=5} E;
module top;
E e;
initial begin
e=LOW; if(e.first()!=HIGH || e.last()!=MID || e.num()!=3) $fatal;
$display("PASS"); $finish;
end
endmodule
