// RUN: %target_clang %target_pic -I%resource_dir/include -c %S/Inputs/dpi_open_array_output_selectors.c -o %t.o
// RUN: %talos --execution-tier=native %s %t.o -o %t.native
// RUN: %t.native | FileCheck %s
// RUN: %talos --execution-tier=bytecode %s %t.o -o %t.bytecode
// RUN: %t.bytecode | FileCheck %s

module top;
  import "DPI-C" function void fill_plain(output int rows[][]);
  import "DPI-C" context function int fill(output int rows[][], input int before_call, after_call);
  import "DPI-C" pure function int select_row(input int selector[]);
  export "DPI-C" function observe_index;
  int index, picks, group;
  bit choose_call, flip_choice, resize_sizes;
  int sizes[];
  int selectors[2][1];
  int rows[4][1][];
  int grid[2][2][1][];

  function automatic int observe_index(input int expected, next_index);
    int original = index;
    index = next_index;
    if (flip_choice) choose_call = !choose_call;
    if (resize_sizes) sizes = new[2];
    return original == expected;
  endfunction
  function int pick();
    ++picks;
    return group;
  endfunction

  initial begin
    rows[0][0] = '{10, 11};
    rows[1][0] = '{20, 21};
    rows[2][0] = '{30};
    rows[3][0] = '{40, 41};
    fill_plain(rows[index++]);
    if (index != 1 || rows[0][0][0] != 5 || rows[1][0][0] != 20)
      $fatal(1, "postincrement evaluated more than once");

    index = 0;
    if (!fill(rows[index++], 0, 1) || index != 2 || rows[0][0][0] != 5 ||
        rows[1][0][0] != 99)
      $fatal(1, "postincrement around a context call");

    // Predecrement selects row 1 to supply the shape and row 2 for copy-out.
    index = 2;
    if (!fill(rows[--index], 2, 3) || index != 2 || rows[2][0][0] != 99 ||
        rows[2][0].size() != 2)
      $fatal(1, "predecrement around a context call");

    // The unselected function must never execute. The selected increment
    // is evaluated for its side effect only on return.
    index = 0;
    if (!fill(rows[choose_call ? pick() : index++], 0, 3) || picks != 0 ||
        index != 4 || rows[3][0][0] != 99)
      $fatal(1, "conditional output selector");

    // A function needed to find the shape is called once. The independent
    // index is evaluated again when the output is assigned.
    grid[0][0][0] = '{1, 2};
    grid[0][1][0] = '{3, 4};
    index = 0;
    if (!fill(grid[pick()][index], 0, 1) || picks != 1 ||
        grid[0][0][0][0] != 1 || grid[0][1][0][0] != 99)
      $fatal(1, "cached function result and live index");

    // A previously inactive call can become necessary on return.
    index = 0;
    group = 1;
    flip_choice = 1;
    rows[1][0] = '{20, 21};
    if (!fill(rows[choose_call ? pick() : index++], 0, 0) || picks != 2 ||
        index != 0 || rows[1][0][0] != 99)
      $fatal(1, "newly selected function on return");

    // Both the array inquiry and the method use the callback's new array size.
    flip_choice = 0;
    resize_sizes = 1;
    sizes = new[1];
    rows[1][0] = '{20, 21};
    rows[2][0] = '{30, 31};
    if (!fill(rows[($size(sizes) + sizes.size()) / 2], 0, 0) ||
        rows[1][0][0] != 20 ||
        rows[2][0][0] != 99)
      $fatal(1, "live array size on return");

    // A pure import selecting the output row may itself take an open array.
    resize_sizes = 0;
    index = 0;
    selectors[1][0] = 1;
    if (!fill(rows[select_row(selectors[index++])], 0, 1) || index != 2 ||
        rows[0][0][0] != 5 || rows[1][0][0] != 99)
      $fatal(1, "postincrement in a nested open-array input");
    $display("PASS");
  end
endmodule

// CHECK: PASS
