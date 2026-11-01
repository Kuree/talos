// CLAUSE: $showvars optional interface
// XFAIL: *
// The optional $showvars system interface is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int n=1;
initial begin
$showvars(n);
$display("PASS");$finish;
end
endmodule
