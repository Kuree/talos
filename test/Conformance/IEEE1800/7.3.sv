// CLAUSE: union untagged dynamic error
// XFAIL: *
// 7.3 permits dynamic member types only in tagged unions, but the frontend accepts an untagged string member.
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
typedef union {int value; string text;} U;
initial begin

$display("PASS"); $finish;
end
endmodule
