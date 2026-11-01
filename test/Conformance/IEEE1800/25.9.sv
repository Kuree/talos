// CLAUSE: full to modport virtual assignment
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface Bus; int data=0; modport source(output data); endinterface
module top; Bus a(); virtual Bus raw; virtual Bus.source selected;
initial begin raw=a; selected=raw; selected.data=7; #1; if(a.data!=7) $fatal; $display("PASS"); $finish; end
endmodule
