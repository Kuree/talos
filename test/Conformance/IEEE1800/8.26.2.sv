// CLAUSE: interface implements concrete class error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

class B; endclass
class C implements B; endclass
module top;

initial begin

$display("PASS"); $finish;
end
endmodule
