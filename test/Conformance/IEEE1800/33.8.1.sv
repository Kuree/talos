// CLAUSE: Command-line library priority overrides map order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --libmap %S/Inputs/33.8.1/map.lib -Xslang -L -Xslang slow -Xslang -L -Xslang fast %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;leaf a(),b();initial begin #1;if(a.V!=22||b.V!=22)$fatal(1,"library binding");$display("PASS");$finish;end endmodule
