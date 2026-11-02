// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -c -fPIC %t/probe.c -I%resource_dir/include -o %t/probe.o
// RUN: talos --vpi=full --execution-tier=bytecode %t/mixed.sv %t/probe.o -o %t/mixed
// RUN: %t/mixed | FileCheck %s --check-prefix=MIXED
// RUN: talos --vpi=full --execution-tier=bytecode %t/none.sv %t/probe.o -o %t/none
// RUN: %t/none | FileCheck %s --check-prefix=NONE

// IEEE 1800-2023 E.4 to E.7: a module under no delay-mode directive reports
// vpiDelayModeNone (1) without an error, though only a directive leaves a record.

//--- probe.c
#include "vpi_user.h"
#include <stdio.h>
void probe(const char *name) {
  vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
  s_vpi_error_info error;
  int mode = vpi_get(vpiDefDelayMode, handle);
  printf("%s mode=%d error=%d\n", name, mode, vpi_chk_error(&error));
  fflush(stdout);
}

//--- mixed.sv
module before_directive; endmodule
`delay_mode_zero
module under_directive; endmodule
`resetall
module after_reset; endmodule
module top;
  import "DPI-C" context function void probe(string name);
  before_directive a();
  under_directive b();
  after_reset c();
  initial begin
    probe("top.a");
    probe("top.b");
    probe("top.c");
    $finish;
  end
endmodule
// MIXED: top.a mode=1 error=0
// MIXED: top.b mode=5 error=0
// MIXED: top.c mode=1 error=0

//--- none.sv
module top;
  import "DPI-C" context function void probe(string name);
  initial begin
    probe("top");
    $finish;
  end
endmodule
// NONE: top mode=1 error=0
