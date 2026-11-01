// CLAUSE: procedural assertion automatic loop capture
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; bit clk=0; bit[3:0] data=15; int passes=0,failures=0;
always @(posedge clk) for(int i=0;i<4;i++) begin
 ap: assert property(data[i]) passes++; else failures++;
end
initial begin #1; clk=1; #1; if(passes!=4 || failures!=0) $fatal(1,"passes=%0d failures=%0d",passes,failures); $display("PASS"); $finish; end
endmodule
