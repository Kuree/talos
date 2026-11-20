// RUN: %target_clang %target_pic -I%resource_dir/include -c %S/Inputs/dpi_open_array_sized_outer.c -o %t.o
// RUN: %talos --execution-tier=native %s %t.o -o %t.native
// RUN: %t.native | FileCheck %s
// RUN: not %t.native +wrong-size 2>&1 | FileCheck %s --check-prefix=BAD
// RUN: %talos --execution-tier=bytecode %s %t.o -o %t.bytecode
// RUN: %t.bytecode | FileCheck %s
// RUN: not %t.bytecode +wrong-size 2>&1 | FileCheck %s --check-prefix=BAD

module top;
  import "DPI-C" function int read_rows(input int rows[4:3][]);
  import "DPI-C" function void edit_rows(inout int rows[4:3][]);
  int rows[][];
  initial begin
    rows = new[$test$plusargs("wrong-size") ? 3 : 2];
    rows[0] = '{11, 12};
    rows[1] = '{21};
    if (!read_rows(rows)) $fatal(1, "sized outer dimension");
    edit_rows(rows);
    if (rows[0][1] != 32 || rows[1][0] != 41) $fatal(1, "copy-out order");
    $display("PASS");
  end
endmodule

// CHECK: entered read_rows
// CHECK: PASS
// BAD-NOT: entered read_rows
// BAD: simulation ended: format argument mismatch (status 8)
// BAD-NOT: entered read_rows
