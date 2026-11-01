// CLAUSE: A configuration rebinds cells across libraries by instance and by use; a missing design cell is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %S/Inputs/33/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier --libmap %S/Inputs/33/lib.map %s -o %t.exe
// RUN: %t.exe
// DIAG: 'work.missing' is not a valid top-level module
// CHECK: a=7 b=29 c=31{{$}}

// Clause 33: three instances of one cell end up with three bindings from the library map and configuration.
module leaf #(parameter int VALUE = 7);
endmodule
module top;
  leaf a();
  leaf b();
  leaf c();
  initial begin
    $display("a=%0d b=%0d c=%0d", a.VALUE, b.VALUE, c.VALUE);
    $finish;
  end
endmodule
config selected_config;
  design work.top;
  default liblist work;
  instance top.b liblist gates;
  instance top.c use gates.other;
endconfig
