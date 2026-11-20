// RUN: not talos -emit-talos %s 2>&1 | FileCheck %s

module dpi_open_array_shape_invalid;
  import "DPI-C" function void consume(input int rows[][2]);
  int wrong_size[3][3];
  int wrong_rank[3];
  shortint wrong_leaf[3][2];
  int associative[string][2];
  initial begin
    consume(wrong_size);
    consume(wrong_rank);
    consume(wrong_leaf);
    consume(associative);
  end
endmodule

// CHECK: error:
// CHECK-NEXT: consume(wrong_size)
// CHECK: error:
// CHECK-NEXT: consume(wrong_rank)
// CHECK: error:
// CHECK-NEXT: consume(wrong_leaf)
// CHECK: error:
// CHECK-NEXT: consume(associative)
