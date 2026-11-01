// CLAUSE: implicit net
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
assign implicit_wire=1;
initial begin
#1;if($bits(implicit_wire)!=1||implicit_wire!==1)$fatal(1,"implicit scalar net");
$display("PASS");$finish;
end
endmodule
