// CLAUSE: minimum vector width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[65535:0] n;
initial begin
n='0;n[65535]=1;if($bits(n)!=65536||n[65535]!==1)$fatal(1,"vector width");
$display("PASS");$finish;
end
endmodule
