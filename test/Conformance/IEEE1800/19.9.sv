// CLAUSE: coverage system query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;bit v;covergroup G;cp:coverpoint v;endgroup G g;
initial begin g=new;g.sample();if($get_coverage()<=0)$fatal;$display("PASS");$finish;end endmodule
