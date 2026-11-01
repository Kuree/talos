// CLAUSE: array literal nested replication
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2][6];
initial begin
a='{2{'{3{4,5}}}}; foreach(a[i,j]) if(a[i][j]!=(j%2==0?4:5)) $fatal;
$display("PASS"); $finish;
end
endmodule
