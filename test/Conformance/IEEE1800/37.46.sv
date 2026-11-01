// CLAUSE: Net drivers and loads: vpiDriver and vpiLoad give a net's assignments, primitive terminals and ports, and a complex port expression is a load reachable through vpiHighConn
// XFAIL: *
// load iteration misses the port load and reports loads=2 for a net with 3 loads
// RUN: %clang -c -fPIC %S/Inputs/37.46/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: top.w driver vpiContAssign
// CHECK-DAG: top.w driver vpiPrimTerm
// CHECK: top.w drivers=2
// CHECK-DAG: top.w load vpiContAssign
// CHECK-DAG: top.w load vpiPrimTerm
// CHECK-DAG: top.w load vpiPort high=!w
// CHECK: top.w loads=3
// CHECK: top.from_port driver vpiPort
// CHECK: top.from_port drivers=1
// CHECK: top.quiet drivers=0
// CHECK: top.quiet loads=0

// Detail 1: sink's input connection !w is the my_module/ram example of the clause.
module src(output wire o);
  assign o = 1'b1;
endmodule
module sink(input wire p);
endmodule
module top;
  logic a = 1, b = 1;
  wire w, o1, o2, from_port, quiet;
  assign w = a;
  buf g(w, b);
  src s(from_port);
  assign o1 = ~w;
  buf h(o2, w);
  sink k(!w);
  import "DPI-C" context function void probe();
  initial begin
    #1 probe();
    $finish;
  end
endmodule
