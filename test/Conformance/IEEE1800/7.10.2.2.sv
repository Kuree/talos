// CLAUSE: queue unknown method index
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int q[$]; integer index=32'hx;
initial begin
q='{7,9}; q.insert(index,11); q.delete(index); if(q.size()!=2 || q[0]!=7 || q[1]!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
