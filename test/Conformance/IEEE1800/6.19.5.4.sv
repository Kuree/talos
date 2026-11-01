// CLAUSE: enum next prev wrap
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef enum int {A=2,B=7,C=9} E; E value;
initial begin
value=C; if(value.next()!=A || value.next(4)!=A || value.prev(4)!=B) $fatal; value=A; if(value.prev()!=C) $fatal;
$display("PASS"); $finish;
end
endmodule
