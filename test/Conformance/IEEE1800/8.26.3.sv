// CLAUSE: interface implements types not inherited error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

interface class I; typedef int T; pure virtual function T f(); endclass
class C implements I; T value; virtual function I::T f(); return value; endfunction endclass
module top;

initial begin

$display("PASS"); $finish;
end
endmodule
