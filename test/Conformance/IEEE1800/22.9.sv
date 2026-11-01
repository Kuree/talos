// CLAUSE: unconnected pull
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`unconnected_drive pull1
module sink(input wire value, output wire observed); assign observed=value; endmodule
module top;
wire observed;
sink s(.value(),.observed(observed));
initial begin #1; if(observed!==1) $fatal; $display("PASS"); $finish; end
endmodule
`nounconnected_drive
