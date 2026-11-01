// CLAUSE: assignment ascending truncation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [0:5] dst; logic signed [0:4] signed_dst;
initial begin
dst=8'sh8f; signed_dst=8'sh8f; if(dst!==6'h0f || signed_dst!==5'h0f) $fatal;
$display("PASS"); $finish;
end
endmodule
