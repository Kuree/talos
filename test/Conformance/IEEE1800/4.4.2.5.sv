// CLAUSE: module zero drive before renba
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
 bit clk=0,data=0;
 clocking cb @(posedge clk); output #0 data; endclocking
 initial begin @(cb); cb.data<=1; #0; if(data!=0) $fatal(1,"early=%0d",data); end
 initial begin #1; clk=1; #1; if(data!=1) $fatal; $display("PASS"); $finish; end
endmodule
