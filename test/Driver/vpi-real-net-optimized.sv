// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -c -fPIC %t/probe.c -I%resource_dir/include -o %t/probe.o
// RUN: talos -O3 --vpi=full --execution-tier=native %t/design.sv %t/probe.o -o %t/simulator
// RUN: %t/simulator | FileCheck %s

// IEEE 1800-2023 38.15: vpi_get_value reads a real net's current value. Generated
// code at -O2 and above stores it straight to its own plane, which has to reach the
// state that VPI reads, resolved or not, whatever the optimization level.

//--- probe.c
#include "sv_vpi_user.h"
#include <stdio.h>
void probe(const char *name) {
  vpiHandle net = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
  s_vpi_value value = {.format = vpiRealVal};
  vpi_get_value(net, &value);
  printf("%s=%g\n", name, value.value.real);
  fflush(stdout);
}

//--- design.sv
module top;
  function automatic real sum(input real driver[]);
    real total = 0;
    foreach (driver[i]) total += driver[i];
    return total;
  endfunction
  nettype real resolved with sum;
  nettype real plain;
  resolved two;
  assign two = 1.5;
  assign two = 2.5;
  plain one;
  assign one = 4.0;
  real source = 7.0;
  plain follows;
  assign follows = source;
  import "DPI-C" context function void probe(string name);
  initial begin
    #1 probe("top.two");
    probe("top.one");
    probe("top.follows");
    source = -3.25;
    #1 probe("top.follows");
    $finish;
  end
endmodule
// CHECK: top.two=4
// CHECK: top.one=4
// CHECK: top.follows=7
// CHECK: top.follows=-3.25
