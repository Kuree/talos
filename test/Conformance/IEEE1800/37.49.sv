// CLAUSE: Assertion: vpiAssertion finds each assertion of an instance or design with its directive type, name and source location, and by name
// XFAIL: *
// assertion line is -1 and the design count is 0
// RUN: %clang -c -fPIC %S/Inputs/37.49/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: assertion type=vpiAssert name=p_assert line=20 file=1
// CHECK-DAG: assertion type=vpiAssume name=p_assume line=21 file=1
// CHECK-DAG: assertion type=vpiCover name=p_cover line=22 file=1
// CHECK-DAG: assertion type=vpiRestrict name={{.*}} line=23 file=1
// CHECK-DAG: assertion type=vpiImmediateAssert name=i_assert line=26 file=1
// CHECK-DAG: assertion type=vpiImmediateAssume name=i_assume line=27 file=1
// CHECK-DAG: assertion type=vpiImmediateCover name=i_cover line=28 file=1
// CHECK: instance count=7
// CHECK: design count=7
// CHECK: by name=vpiCover

// Line numbers above are this file's; 39.3.1 gives the NULL, instance and by-name access pinned here.
module top;
  logic clk = 0, a = 1;
  p_assert: assert property (@(posedge clk) a);
  p_assume: assume property (@(posedge clk) a);
  p_cover: cover property (@(posedge clk) a);
  restrict property (@(posedge clk) a);
  import "DPI-C" context function void probe();
  initial begin
    i_assert: assert (a);
    i_assume: assume (a);
    i_cover: cover (a);
    probe();
    $finish;
  end
endmodule
