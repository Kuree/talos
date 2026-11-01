// CLAUSE: configuration selection
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf; parameter int VALUE=7; endmodule
module design_top; leaf d(); initial begin if(d.VALUE!=7) $fatal(1,"config selection"); $display("PASS"); $finish; end endmodule
config selected_config;
  design work.design_top;
  default liblist work;
endconfig
