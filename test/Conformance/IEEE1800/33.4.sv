// CLAUSE: A configuration selects instance bindings from libraries; a missing design cell is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %S/Inputs/33.4/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier --libmap %S/Inputs/33.4/lib.map %s -o %t.exe
// RUN: %t.exe
// DIAG: 'work.missing' is not a valid top-level module
// CHECK: a=7 b=29{{$}}

// 33.4: instance b binds to the leaf of library gates, and instance a stays in work.
module leaf #(parameter int VALUE = 7);
endmodule
module top;
  leaf a();
  leaf b();
  initial begin
    $display("a=%0d b=%0d", a.VALUE, b.VALUE);
    $finish;
  end
endmodule

config selected_config;
  design work.top;
  default liblist work;
  instance top.b liblist gates;
endconfig
