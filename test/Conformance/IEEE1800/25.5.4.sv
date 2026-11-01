// CLAUSE: static modport concat control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface Bus; bit a=0,b=0; modport source(output .word({a,b})); endinterface
module Driver(Bus.source bus); initial bus.word=2'b10; endmodule
module top; Bus bus(); Driver driver(bus);
initial begin #1; if(!bus.a || bus.b) $fatal; $display("PASS"); $finish; end
endmodule
