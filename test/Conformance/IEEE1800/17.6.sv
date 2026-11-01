// CLAUSE: checker covergroup
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

checker c(input bit clk,input bit value);
covergroup G@(posedge clk);cp:coverpoint value {bins one={1};}endgroup
G g=new;final if(g.get_inst_coverage()!=100)$fatal;
endchecker
module top;bit clk,v=1;c inst(clk,v);
initial begin #1;clk=1;#1;$display("PASS");$finish;end endmodule
