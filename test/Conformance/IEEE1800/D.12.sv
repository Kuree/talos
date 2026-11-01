// CLAUSE: $showscopes optional interface
// XFAIL: *
// The optional $showscopes system interface is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
$showscopes(0);
$display("PASS");$finish;
end
endmodule
