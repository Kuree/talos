// CLAUSE: Hierarchical and virtual-interface DPI calls use the declaration instance
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/H.9.1/scope.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

interface bus;
  import "DPI-C" context function string where_am_i();
  import "DPI-C" context task read_scope(output string name);
endinterface

module top;
  bus a(), b();
  virtual bus selected;
  string name;
  initial begin
    if (a.where_am_i() != "top.a") $fatal(1, "hierarchical call");
    selected = b;
    if (selected.where_am_i() != "top.b") $fatal(1, "virtual function scope");
    selected.read_scope(name);
    if (name != "top.b") $fatal(1, "virtual task scope");
    selected = a;
    if (selected.where_am_i() != "top.a") $fatal(1, "reassigned interface");
    $display("PASS");
  end
endmodule
