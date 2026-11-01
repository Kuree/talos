// CLAUSE: parameter external unadorned error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

class C #(int N=1); endclass
module top;

initial begin
if(C::N!=1) $fatal;
$display("PASS"); $finish;
end
endmodule
