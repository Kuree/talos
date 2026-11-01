// CLAUSE: assoc traversal empty preserves arg
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int]; int index=7;
initial begin
if(a.first(index)!=0 || index!=7 || a.last(index)!=0 || index!=7 || a.next(index)!=0 || index!=7 || a.prev(index)!=0 || index!=7) $fatal(1,"index=%0d",index);
$display("PASS"); $finish;
end
endmodule
