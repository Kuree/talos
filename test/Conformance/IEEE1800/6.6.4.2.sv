// CLAUSE: trireg charge retention
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
trireg (medium) n; reg en=0; bufif1(n,1'b1,en);
initial begin
#1; if(n!==1'bx) $fatal(1,"initial n=%b",n); en=1; #1; if(n!==1) $fatal; en=0; #1; if(n!==1) $fatal(1,"lost charge n=%b",n);
$display("PASS"); $finish;
end
endmodule
