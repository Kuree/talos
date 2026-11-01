// CLAUSE: Module paths delay outputs from input ports; internal path sources are rejected
// XFAIL: *
// compiler rejects a module path to a variable driven by always @*, which 30.4.1 allows (net or variable output port)
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/30.4.1/source.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/30.4.1/destination.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: specify path source 'internal' must be an 'input' or 'inout' net or modport port
// DIAG: specify path destination 'internal' must be an 'output' or 'inout' net, variable, or modport port
// CHECK: 2 y=0{{$}}
// CHECK-NEXT: 3 q=0{{$}}
// CHECK-NEXT: 12 y=1{{$}}
// CHECK-NEXT: 13 q=1{{$}}
// CHECK-NEXT: 22 y=0{{$}}
// CHECK-NEXT: 23 q=0{{$}}

// 30.4.1: a legal source and legal net and variable destinations, whose delays show in the transition times.
module cell_t(input wire a, output wire y, output reg q);
  timeunit 1ns; timeprecision 1ns;
  assign y = a;
  always @* q = a;
  specify
    (a => y) = 2;
    (a => q) = 3;
  endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  logic a = 0;
  wire y, q;
  cell_t d(a, y, q);
  always @(y) $display("%0t y=%b", $time, y);
  always @(q) $display("%0t q=%b", $time, q);
  initial begin
    #10 a = 1;
    #10 a = 0;
    #10 $finish;
  end
endmodule
