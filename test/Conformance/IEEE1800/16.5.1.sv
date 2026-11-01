// CLAUSE: preponed action sample
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit clk,data; int hits;
always @(posedge clk) data<=1;
ap: assert property (@(posedge clk) data==0)
  begin if($sampled(data)!==0 || data!==1) $fatal(1,"sample/current mismatch"); hits++; end
  else $fatal(1,"not preponed");
initial begin #1; clk=1; #1; if(hits!=1) $fatal; $display("PASS"); $finish; end
endmodule
