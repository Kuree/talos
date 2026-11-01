// CLAUSE: bin value width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;bit[1:0]v;
covergroup G;cp:coverpoint v {bins b={6};}endgroup G g;int hit,total;
initial begin g=new;v=2;g.sample();void'(g.cp.get_inst_coverage(hit,total));if(total!=0 || hit!=0)$fatal;$display("PASS");$finish;end endmodule
