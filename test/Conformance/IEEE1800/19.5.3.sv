// CLAUSE: automatic bins
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit [1:0]v;
covergroup G;cp:coverpoint v;endgroup G g;int hit,total;
initial begin g=new;g.sample();void'(g.get_inst_coverage(hit,total));if(total!=4 || hit!=1)$fatal;$display("PASS");$finish;end endmodule
