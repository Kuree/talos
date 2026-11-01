// CLAUSE: Hierarchical configurations
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module leaf;parameter P=7;endmodule
module alt;parameter P=9;endmodule
module top;leaf u();initial begin if(u.P!=9)$fatal(1,"binding");$display("PASS");$finish;end endmodule
config child;design work.alt;default liblist work;endconfig
config selected;design work.top;default liblist work;instance top.u use work.child:config;endconfig
