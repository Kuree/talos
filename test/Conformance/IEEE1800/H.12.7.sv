// CLAUSE: C-compatible elements in nonrectangular open arrays
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/H.12.7/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function int edit(inout int rows[][]);
  int rows[][];
  initial begin
    rows = new[3];
    rows[0] = '{4};
    rows[2] = '{5, 8, 13};
    if (!edit(rows) || rows[0][0] != 6 || rows[1].size() != 0 ||
        rows[2][2] != 14) $fatal(1, "ragged element access");
    $display("PASS");
  end
endmodule
