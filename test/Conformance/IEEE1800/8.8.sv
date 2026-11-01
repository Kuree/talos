// CLAUSE: typed ctor incompatible error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

class A; endclass
class B; endclass
module top;
A a;
initial begin
a=B::new;
$display("PASS"); $finish;
end
endmodule
