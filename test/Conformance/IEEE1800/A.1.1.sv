// CLAUSE: External cell declared by a library map
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=selected --libmap %S/Inputs/A.1.1/cells.map %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf u();initial begin if(u.P!=7)$fatal;$display("PASS");end endmodule
config selected;design work.top;default liblist work;instance top.u use cells.leaf;endconfig
