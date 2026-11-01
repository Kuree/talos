// CLAUSE: named block self disable
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int value;
initial begin
begin : chosen value=1; disable chosen; value=2; end if(value!=1) $fatal;
$display("PASS"); $finish;
end

endmodule
