// RUN: %target_clang %target_pic -c %S/Inputs/dpi_context_reentry.c -I%resource_dir/include -o %t.o
// RUN: %talos %s %t.o -o %t.native
// RUN: %t.native | FileCheck %s
// RUN: %talos --execution-tier=bytecode %s %t.o -o %t.bytecode
// RUN: %t.bytecode | FileCheck %s

module dpi_context_reentry;
  import "DPI-C" context task enter();
  import "DPI-C" function int check_plain();
  import "DPI-C" context function int check_nested();
  export "DPI-C" task reenter;
  task automatic reenter(output int ok);
    #1;
    ok = check_plain() && check_nested();
  endtask

  initial enter();
endmodule

// CHECK: nested=1 restored=1
