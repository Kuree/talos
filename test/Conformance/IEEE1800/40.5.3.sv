// CLAUSE: vpi_control stops, resets, starts, saves and merges coverage as the system functions do
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/40.5.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full --coverage=toggle %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: collected=1
// CHECK: stop=1
// CHECK: stopped unchanged=1
// CHECK: start=1
// CHECK: restarted grew=1
// CHECK: save=1
// CHECK: reset=1
// CHECK: after reset=0
// CHECK: merge=1
// CHECK: union full=1
// CHECK: check=1

// 40.5.3: "The semantics and behavior are per the $coverage_control() system function". Stop must freeze the count, which
// a no-op would not, since r toggles while stopped. Save and merge name the same database entry. The results are read
// with $coverage_get on the controlled instance.
module dut;
  bit q, r, s;
endmodule
module top;
  dut d();
  import "DPI-C" context function int act(input int code);
  import "DPI-C" context function int save_as(input string name);
  import "DPI-C" context function int merge_from(input string name);
  int prior;
  initial begin
    #1 d.q = 1; #1 d.q = 0; #1;
    prior = $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d);
    $display("collected=%0d", prior > 0);
    $display("stop=%0d", act(1));
    #1 d.r = 1; #1 d.r = 0; #1;
    $display("stopped unchanged=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) == prior);
    $display("start=%0d", act(0));
    #1 d.r = 1; #1 d.r = 0; #1;
    $display("restarted grew=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) > prior);
    prior = $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d);
    $display("save=%0d", save_as("vpi_probe"));
    $display("reset=%0d", act(2));
    $display("after reset=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    #1 d.s = 1; #1 d.s = 0; #1;
    $display("merge=%0d", merge_from("vpi_probe"));
    $display("union full=%0d", $coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d) == $coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d));
    $display("check=%0d", act(3));
    $finish;
  end
endmodule
