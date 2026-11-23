// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -fPIC -c %t/leaf.c -o %t/leaf.o
// RUN: talos -O3 --mlir-timing --vpi=read --top=top %t/design.sv %t/leaf.o -o %t/leaf 2> %t/leaf.log && FileCheck %s --check-prefix=ABSENT < %t/leaf.log
// RUN: %t/leaf | FileCheck %s --check-prefix=LEAF
// RUN: %target_clang -O2 -fPIC -I%resource_dir/include -c %t/reader.c -o %t/reader.o
// RUN: talos -O3 --vpi=read --top=top %t/design.sv %t/reader.o -o %t/reader
// RUN: %t/reader | FileCheck %s --check-prefix=READ
// RUN: talos -O3 --vpi=read --top=top -c %t/design.sv -o %t/open.o && llvm-readelf -sW %t/open.o | FileCheck %s --check-prefix=OPEN
// ABSENT: talos VPI: no reachable reader in native link
// LEAF: result=17
// READ: result=42
// OPEN: __talos_design_database_v1

//--- design.sv
module unused;
  import "DPI-C" context function int other();
endmodule
module top #(parameter type word_t = logic [7:0]);
  import "DPI-C" context function int probe();
  word_t value;
  initial begin
    value = 42;
    #1 $display("result=%0d", probe());
  end
endmodule
//--- leaf.c
int probe(void) { return 17; }
//--- reader.c
#include "vpi_user.h"
int probe(void) {
  vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)"top.value", 0);
  s_vpi_value result = {.format = vpiIntVal};
  if (!handle)
    return -1;
  vpi_get_value(handle, &result);
  return result.value.integer;
}

//--- indirect.c
static int result(void) { return 17; }
static int (*volatile target)(void) = result;
int probe(void) { return target(); }
