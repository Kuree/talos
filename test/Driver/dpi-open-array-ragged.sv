// RUN: %target_clang %target_pic -c %S/Inputs/dpi_open_array_ragged_impl.c -I%resource_dir/include -o %t.o
// RUN: %talos --target=native -o %t.native %s %t.o
// RUN: %t.native | FileCheck %s
// RUN: %talos --execution-tier=bytecode -o %t.bytecode %s %t.o
// RUN: %t.bytecode | FileCheck %s

module dpi_open_array_ragged;
  import "DPI-C" function int edit(inout logic [7:0] rows[][][]);
  logic [7:0] rows[2:1][][];
  initial begin
    rows[1] = new[3];
    rows[1][1] = '{8'hxz, 8'h27};
    rows[2] = new[2];
    rows[2][0] = '{8'hfe};
    if (!edit(rows)) $fatal(1, "ragged layout");
    $display("values=%h,%h lengths=%0d,%0d,%0d", rows[1][1][0], rows[2][0][0],
             rows[1][0].size(), rows[1][1].size(), rows[2][0].size());
  end
endmodule

// CHECK: values=fe,xz lengths=0,2,1
