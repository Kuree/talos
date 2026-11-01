// CLAUSE: system exit status
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int rc;
initial begin
rc=$system("exit 0");if(rc!=0)$fatal;
$display("PASS");$finish;
end
endmodule
