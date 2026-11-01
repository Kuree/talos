// CLAUSE: Covergroup declaration and bin syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int n;covergroup C;cp:coverpoint n {bins seven={7};}endgroup C c;
initial begin c=new;n=7;c.sample();if(c.get_inst_coverage()!=100.0)$fatal(1,"result"); $display("PASS");end
endmodule
