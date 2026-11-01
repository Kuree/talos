// CLAUSE: switch processing
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
tri n;wire source=1'b1;logic en=1;tranif1 sw(n,source,en);
initial begin
#1;if(n!==1)$fatal(1,"switch on");en=0;#1;if(n!==1'bz)$fatal(1,"switch off");
$display("PASS");$finish;
end
endmodule
