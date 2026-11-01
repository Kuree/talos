// CLAUSE: forward typedef cycle
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

typedef class B; class A; B other; endclass
class B; A other; endclass
module top;
A a; B b;
initial begin
a=new; b=new; a.other=b; b.other=a; if(a.other.other!==a) $fatal;
$display("PASS"); $finish;
end
endmodule
