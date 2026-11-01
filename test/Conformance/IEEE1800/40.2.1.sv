// CLAUSE: SystemVerilog coverage API
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=toggle -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit q;
initial begin
if($coverage_get_max(23,10,top)<0)$fatal(1,"coverage API");
$display("PASS");$finish;
end
endmodule
