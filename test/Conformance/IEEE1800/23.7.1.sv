// CLAUSE: package class prefix
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package P;class C;static int value=7;endclass endpackage
module top;

initial begin
if(P::C::value!=7)$fatal;
$display("PASS");$finish;
end
endmodule
