// XFAIL: *
// Slang 11.0 and 12.2 reject the bounded inout queue permitted by 7.7.
// RUN: %target_clang %target_pic -c %S/Inputs/dpi_open_array_bindings.c -I%resource_dir/include -o %t.o
// RUN: %talos --target=native %s %t.o -o %t.native
// RUN: %t.native | FileCheck %s
// RUN: %talos --execution-tier=bytecode %s %t.o -o %t.bytecode
// RUN: %t.bytecode | FileCheck %s

module dpi_open_array_slang_xfail;
  import "DPI-C" function int inspect(input int values[][0:1],
                                      inout int q[]);
  int q[$:3];
  int rows[1:0][0:1];
  initial begin
    rows[0] = '{10, 11};
    rows[1] = '{20, 21};
    q = '{1, 2, 3};
    if (inspect(.q(q), .values(rows)) != 1) $fatal(1, "mixed ranges");
    $display("queue size=%0d last=%0d", q.size(), q[2]);
  end
endmodule

// CHECK: queue size=3 last=21
