// CLAUSE: specparam
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
specparam D=2;
initial begin
#D;if($time!=2)$fatal(1,"specparam delay");
$display("PASS");$finish;
end
endmodule
