// CLAUSE: Named module instance with parameter override
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child #(parameter P=7)(output wire[3:0]y);assign y=P;endmodule
module top;
wire[3:0]y;child #(.P(5))u(.y(y));
initial begin #1;if(y!==5)$fatal(1,"result"); $display("PASS");end
endmodule
