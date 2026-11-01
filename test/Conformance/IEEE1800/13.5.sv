// CLAUSE: output argument scalar control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value; task automatic produce(output int result); result=7; endtask
initial begin
produce(value); if(value!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
