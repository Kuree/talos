// CLAUSE: line directive sets filename and line
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`line 100 "virtual.sv" 0
module top;
initial begin
 if(`__LINE__!=102 || `__FILE__!="virtual.sv") $fatal(1,"source location");
 $display("PASS"); $finish;
end
endmodule
