// CLAUSE: cross illegal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit a,b;covergroup G;
x:cross a,b {illegal_bins omitted=binsof(a) intersect {0} && binsof(b) intersect {0};}
endgroup G g;int hit,total;
initial begin g=new;a=1;b=1;g.sample();void'(g.x.get_inst_coverage(hit,total));if(total!=3)$fatal;$display("PASS");$finish;end endmodule
