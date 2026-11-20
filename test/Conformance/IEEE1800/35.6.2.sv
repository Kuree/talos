// CLAUSE: Output and inout actuals receive their values at return from a DPI import
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/35.6.2/probe.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int selected = 0;
  int rows[2][2] = '{'{10, 20}, '{30, 40}};
  export "DPI-C" function select_second;
  function void select_second();
    selected = 1;
  endfunction
  import "DPI-C" context function int edit(inout int values[]);
  import "DPI-C" function void fill(output int values[], output int n);

  int original, n;
  initial begin
    original = edit(rows[selected]);
    if (original != 10 || selected != 1 || rows[0][0] != 10 || rows[0][1] != 20 ||
        rows[1][0] != 99 || rows[1][1] != 20) $fatal(1, "inout copy-out address");

    selected = 0;
    fill(rows[selected++], n);
    if (selected != 1 || rows[0][0] != 5 || rows[0][1] != 6 ||
        rows[1][0] != 99 || rows[1][1] != 20 || n != 7)
      $fatal(1, "output address evaluated once on return");
    $display("PASS");
  end
endmodule
