// CLAUSE: Undriven wire values remain high impedance
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
wire n;
initial begin
#1;if(n!==1'bz)$fatal(1,"undriven wire");
$display("PASS");$finish;
end
endmodule
