// CLAUSE: A cell clause redirects every matching instance; a library-qualified cell with a liblist is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %S/Inputs/33.4.1.4/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier --libmap %S/Inputs/33.4.1.4/lib.map %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot specify a liblist when using a cell rule that targets a specific library already
// CHECK: leaf 29 29{{$}}
// CHECK-NEXT: leaf2 30 30{{$}}
// CHECK-NEXT: other 9{{$}}

// 33.4.1.4: both forms of the clause, unqualified with a liblist and library-qualified with use, at both levels.
module leaf #(parameter int VALUE = 7);
endmodule
module leaf2 #(parameter int VALUE = 8);
endmodule
module other #(parameter int VALUE = 9);
endmodule
module sub;
  leaf c();
  leaf2 d();
endmodule
module top;
  leaf a();
  leaf2 b();
  other o();
  sub s();
  initial begin
    $display("leaf %0d %0d", a.VALUE, s.c.VALUE);
    $display("leaf2 %0d %0d", b.VALUE, s.d.VALUE);
    $display("other %0d", o.VALUE);
    $finish;
  end
endmodule
config selected_config;
  design work.top;
  default liblist work;
  cell leaf liblist gates;
  cell work.leaf2 use gates.leaf2;
endconfig
