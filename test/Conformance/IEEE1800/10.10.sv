// CLAUSE: unpacked concat empty
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int d[],q[$];
initial begin
d='{7}; q='{9}; d={}; q={}; if(d.size()!=0 || q.size()!=0) $fatal;
$display("PASS"); $finish;
end
endmodule
