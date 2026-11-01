// CLAUSE: assoc default increment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int]='{default:7};
initial begin
a[1]++; if(a.num()!=1 || a[1]!=8) $fatal(1,"value=%0d size=%0d",a[1],a.num());
$display("PASS"); $finish;
end
endmodule
