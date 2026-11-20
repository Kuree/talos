// CLAUSE: Open unpacked dimensions and type equivalence of sized inner dimensions
// SINCE: 0.2.0
// RUN: %not %talos --std=1800-2023 --top=top -DDYNAMIC_ROWS -emit-talos %s -o %t.bad.mlir
// RUN: %clang -c -fPIC %S/Inputs/35.5.6.1/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// DIAG: value of type 'int$[3:2][]' cannot be assigned to type 'int$[][5:6]'
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function int inspect(input int rows[][5:6], output int result[][]);
`ifdef DYNAMIC_ROWS
  // 7.6 requires equivalent row types even when every dynamic row has two elements.
  int rows[3:2][];
`else
  int rows[3:2][8:7];
`endif
  int result[3:2][];
  initial begin
    rows[3] = '{11, 12};
    rows[2] = '{21, 22};
    result[3] = new[1];
    result[2] = new[2];
    if (!inspect(rows, result) || result[3][0] != 11 || result[2][1] != 22)
      $fatal(1, "mixed open-array dimensions");
    $display("PASS");
  end
endmodule
