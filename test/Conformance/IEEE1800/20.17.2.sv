// CLAUSE: stacktrace
// XFAIL: *
// The standard $stacktrace system task is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
$stacktrace;
$display("PASS");$finish;
end
endmodule
