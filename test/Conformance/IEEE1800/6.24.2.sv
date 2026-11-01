// CLAUSE: enum cast failure retains value
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface class I; endclass
class C implements I; endclass
module top;
C c,d; I i;
initial begin
c=new; i=c; if(!$cast(d,i) || d!==c) $fatal;
$display("PASS"); $finish;
end
endmodule
