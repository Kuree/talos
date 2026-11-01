// CLAUSE: Generate loop creates parameterized instances
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module child #(parameter P=0);endmodule
module top;
for(genvar i=0;i<2;i++)begin:g child #(i+1)u();end
initial begin if(g[0].u.P!=1 || g[1].u.P!=2)$fatal(1,"result"); $display("PASS");end
endmodule
