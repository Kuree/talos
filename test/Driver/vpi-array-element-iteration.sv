// RUN: %target_clang %target_pic -c %S/Inputs/vpi-array-element-iteration.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=read -O3 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 37.17: vpi_iterate(vpiReg) returns the variables of an array
// var, its leaf elements (details 9 and 26) in index order with the leftmost
// dimension outermost. 37.20 detail 1: vpiMemoryWord returns them as vpiReg
// objects, so an int array has none. Talos does not create var select objects
// (37.19) yet, nor reach the elements of an array with a dynamic dimension, so
// those iterations give a notice.
module top;
  int ints [3] = '{10, 11, 12};
  logic [7:0] mem [3:1] = '{8'd3, 8'd2, 8'd1};
  logic [3:0] grid [2][0:1] = '{'{4'd1, 4'd2}, '{4'd3, 4'd4}};
  int fa [2][];
  import "DPI-C" context function void probe();
  initial begin
    fa[0] = new[2];
    #1 probe();
  end
endmodule

// CHECK: top.ints
// CHECK-NEXT:   vpiReg: top.ints[0]=vpiIntVar:10 top.ints[1]=vpiIntVar:11 top.ints[2]=vpiIntVar:12
// CHECK-NEXT:   vpiMemoryWord: none
// CHECK-NEXT:   vpiVarSelect: var select objects of an array are not available through VPI
// CHECK-NEXT:   vpiVarSelect: none
// CHECK-NEXT: top.mem
// CHECK-NEXT:   vpiReg: top.mem[3]=vpiReg:3 top.mem[2]=vpiReg:2 top.mem[1]=vpiReg:1
// CHECK-NEXT:   vpiMemoryWord: top.mem[3]=vpiReg:3 top.mem[2]=vpiReg:2 top.mem[1]=vpiReg:1
// CHECK-NEXT:   vpiVarSelect: var select objects of an array are not available through VPI
// CHECK-NEXT:   vpiVarSelect: none
// CHECK-NEXT: top.grid
// CHECK-NEXT:   vpiReg: top.grid[0][0]=vpiReg:1 top.grid[0][1]=vpiReg:2 top.grid[1][0]=vpiReg:3 top.grid[1][1]=vpiReg:4
// CHECK-NEXT:   vpiMemoryWord: top.grid[0][0]=vpiReg:1 top.grid[0][1]=vpiReg:2 top.grid[1][0]=vpiReg:3 top.grid[1][1]=vpiReg:4
// CHECK-NEXT:   vpiVarSelect: var select objects of an array are not available through VPI
// CHECK-NEXT:   vpiVarSelect: none
// CHECK-NEXT: top.grid[1]
// CHECK-NEXT:   vpiReg: top.grid[1][0]=vpiReg:3 top.grid[1][1]=vpiReg:4
// CHECK-NEXT:   vpiMemoryWord: top.grid[1][0]=vpiReg:3 top.grid[1][1]=vpiReg:4
// CHECK-NEXT:   vpiVarSelect: var select objects of an array are not available through VPI
// CHECK-NEXT:   vpiVarSelect: none
// CHECK-NEXT: top.fa
// CHECK-NEXT:   vpiReg: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   vpiReg: none
// CHECK-NEXT:   vpiMemoryWord: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   vpiMemoryWord: none
// CHECK-NEXT:   vpiVarSelect: var select objects of an array are not available through VPI
// CHECK-NEXT:   vpiVarSelect: none
