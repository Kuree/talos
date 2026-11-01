// CLAUSE: string packed right justified
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [31:0] a; logic [7:0] b;
initial begin
a="AB"; b="AB"; if(a!==32'h00004142 || b!==8'h42) $fatal;
$display("PASS"); $finish;
end
endmodule
