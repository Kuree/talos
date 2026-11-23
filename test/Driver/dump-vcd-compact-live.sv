// REQUIRES: native-elf
// RUN: rm -rf %t && %split-file %s %t
// RUN: %target_clang -c -fPIC -I%resource_dir/include %t/plugin.c -o %t/plugin.o
// RUN: talos -O3 --compile-threads=1 --vpi=full %t/top.sv %t/plugin.o -o %t/native
// RUN: cd %t && ./native && FileCheck %s --check-prefix=FINAL < original.vcd && FileCheck %s --check-prefix=SIBLINGS < original.vcd
// RUN: mkdir %t/early && cd %t/early && env WAVE_SIGNAL=1 not ../native && FileCheck %s --check-prefix=EARLY < original.vcd
// RUN: mkdir %t/late && cd %t/late && env WAVE_SIGNAL=2 not ../native && FileCheck %s --check-prefix=LATE < original.vcd && FileCheck %s --check-prefix=SIBLINGS < original.vcd
// RUN: talos -O0 --compile-threads=1 --execution-tier=bytecode --vpi=full %t/top.sv %t/plugin.o -o %t/bytecode
// RUN: cd %t && env TALOS_RT_VCD_COMPACT_FILE=bc.vcd ./bytecode && FileCheck %s --check-prefix=FINAL < bc.vcd && FileCheck %s --check-prefix=SIBLINGS < bc.vcd
//
// Independently forceable variables can have the same sampled value for
// a full publication interval. A VPI force then forks their histories
// (21.7.2.3, 38.34).
// EARLY-DAG: $var reg 8 [[AB:[^ ]+]] a [7:0] $end
// EARLY-DAG: $var reg 8 [[AB]] b [7:0] $end
// EARLY: $enddefinitions $end
// EARLY: {{^}}#127{{$}}
// LATE: $var reg 8 [[A:[^ ]+]] a [7:0] $end
// LATE: $var reg 8 [[B:[^ ]+]] b [7:0] $end
// LATE: $dumpvars
// LATE: b0 [[B]]
// LATE: b11111111 [[B]]
// LATE: {{^}}#129{{$}}
// LATE: b1xz01zx [[B]]
// FINAL: $var reg 8 [[A:[^ ]+]] a [7:0] $end
// FINAL: $var reg 8 [[B:[^ ]+]] b [7:0] $end
// FINAL: $var reg 8 [[A]] twin [7:0] $end
// FINAL: $var reg 130 [[W:[^ ]+]] wide [129:0] $end
// FINAL: $var reg 130 [[FORK:[^ ]+]] wide_copy [129:0] $end
// FINAL: $var reg 130 [[W]] wide_twin [129:0] $end
// FINAL-DAG: b0xz{{0+}} [[FORK]]
// FINAL-DAG: b1xz01zx [[B]]
// FINAL: b1011010 [[A]]
// Check the whole value section independently: neither unaffected sibling
// may acquire the value written to the forced signal or to the wide slice.
// SIBLINGS: $var reg 8 [[A:[^ ]+]] a [7:0] $end
// SIBLINGS: $var reg 130 [[W:[^ ]+]] wide [129:0] $end
// SIBLINGS: $enddefinitions $end
// SIBLINGS-NOT: b1xz01zx [[A]]{{$}}
// SIBLINGS-NOT: b0xz{{0+}} [[W]]{{$}}
//--- top.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  logic [7:0] a=0, b=0, twin=0;
  logic [129:0] wide=0, wide_copy=0, wide_twin=0;
  import "DPI-C" context function void gate();
  import "DPI-C" context function void change_force(input int release_it);
  initial begin
    $dumpfile("original.vcd");
    $dumpvars(0, a, b, twin, wide, wide_copy, wide_twin);
    repeat (128) begin
      #1 a = ~a; b = a; twin = a;
      wide = {a, 114'b0, a}; wide_copy = wide; wide_twin = wide;
    end
    #1;
    gate();
    change_force(0);
    wide_copy[91:90] = 2'bxz;
    #1 gate();
    change_force(1);
    #1 a = 8'h5a; b = a; twin = a;
    #1 $finish;
  end
endmodule
//--- plugin.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <signal.h>
#include <stdlib.h>
void gate(void) {
  static int stage;
  const char *signal_at = getenv("WAVE_SIGNAL");
  ++stage;
  if (signal_at && atoi(signal_at) == stage)
    raise(stage == 1 ? SIGTERM : SIGKILL);
}
void change_force(int release_it) {
  vpiHandle b = vpi_handle_by_name((PLI_BYTE8 *)"top.b", 0);
  assert(b);
  s_vpi_value v = {.format=vpiBinStrVal, .value.str=(PLI_BYTE8 *)"01xz01zx"};
  vpi_put_value(b, &v, 0, release_it ? vpiReleaseFlag : vpiForceFlag);
  assert(!vpi_chk_error(0));
  vpi_release_handle(b);
}
