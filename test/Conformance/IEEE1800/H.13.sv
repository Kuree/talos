// CLAUSE: DPI and VPI report package, instance and simulation timescales
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/H.13/dpi_time_min.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

package top;
  timeunit 10ns/1ns;
  int marker;
  import "DPI-C" context function int check_time(input string name, input int unit_exp,
                                                  input int precision_exp, input real now);
endpackage

module top;
  timeunit 1ns/1ps;
  import "DPI-C" context function int check_time(input string name, input int unit_exp,
                                                  input int precision_exp, input real now);
  initial begin
    top::marker = 1;
    #20;
    if (!top::check_time("top::", -8, -9, 2.0)) $fatal(1, "package time");
    if (!check_time("top", -9, -12, 20.0)) $fatal(1, "instance time");
    $display("PASS");
  end
endmodule
