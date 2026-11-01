// CLAUSE: handle arithmetic error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

class C; endclass
module top;
C a;
initial begin
a++;
$display("PASS"); $finish;
end
endmodule
