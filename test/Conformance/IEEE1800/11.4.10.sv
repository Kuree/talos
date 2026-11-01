// CLAUSE: sizing shift unsigned context
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic signed [3:0] s; logic [7:0] u,alone,mixed;
initial begin
s=-8; u=0; alone=s>>>1; mixed=(s>>>1)+u; if(alone!=8'hfc || mixed!=8'h04) $fatal(1,"alone=%h mixed=%h",alone,mixed);
$display("PASS"); $finish;
end
endmodule
