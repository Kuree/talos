// RUN: %target_clang %target_pic -c %S/Inputs/vpi-dynamic-arrays.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=read -O3 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// Module-level dynamic arrays, queues and associative arrays build with VPI.
// IEEE 1800-2023 37.17: vpiArrayType names the kind of array, and vpiSize
// (detail 9) is the number of variables in the array, here the current
// element count; an array with more than one dimension that includes such a
// dimension reports no size yet. vpiIsMemory is TRUE for a one-dimensional
// array (Annex K vpi_user.h). The leftmost range of a dynamic array or queue
// is [0:n-1] for its current size (dyn [0:2] then [0:4], q [0:1], fa[1]
// [0:3]); an associative range, and the range of an empty or unallocated
// array (empty, q after delete, nested), is empty: size 0 and no bounds
// (37.17 detail 6, 37.22 details 1-2). Two answers are Talos choices the LRM
// leaves open: fa's second range, a dynamic dimension that each element sizes
// separately, is empty, and a range handle obtained before a resize reports
// the new size. Elements of these arrays live in a managed container and are
// not reachable through VPI yet.
module top;
  int fixed [3];
  int dyn [];
  int empty [];
  int q [$];
  int aa [string];
  int nested [$][2];
  int fa [2][];
  import "DPI-C" context function void probe();
  import "DPI-C" context function void resized();
  initial begin
    dyn = new[3];
    q.push_back(7);
    q.push_back(8);
    aa["k"] = 2;
    fa[1] = new[4];
    #1 probe();
    dyn = new[5];
    q.delete();
    aa["j"] = 3;
    #1 resized();
  end
endmodule

// CHECK: top.fixed type=vpiRegArray arraytype=1 memory=1
// CHECK-NEXT:   size=3
// CHECK-NEXT:   size: ok
// CHECK-NEXT:   bounds [0:2] ranges [0:2]/3
// CHECK-NEXT:   element found
// CHECK-NEXT:   by_index: ok
// CHECK-NEXT: top.dyn type=vpiRegArray arraytype=2 memory=1
// CHECK-NEXT:   size=3
// CHECK-NEXT:   size: ok
// CHECK-NEXT:   bounds [0:2] ranges [0:2]/3
// CHECK-NEXT:   element none
// CHECK-NEXT:   by_index: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   elements none
// CHECK-NEXT:   iterate: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   top.dyn[0] none
// CHECK-NEXT:   by_name: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT: top.empty type=vpiRegArray arraytype=2 memory=1
// CHECK-NEXT:   size=0
// CHECK-NEXT:   size: ok
// CHECK-NEXT:   bounds [] ranges []/0
// CHECK-NEXT:   element none
// CHECK-NEXT:   by_index: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   elements none
// CHECK-NEXT:   iterate: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   top.empty[0] none
// CHECK-NEXT:   by_name: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT: top.q type=vpiRegArray arraytype=4 memory=1
// CHECK-NEXT:   size=2
// CHECK-NEXT:   size: ok
// CHECK-NEXT:   bounds [0:1] ranges [0:1]/2
// CHECK-NEXT:   element none
// CHECK-NEXT:   by_index: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   elements none
// CHECK-NEXT:   iterate: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   top.q[0] none
// CHECK-NEXT:   by_name: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT: top.aa type=vpiRegArray arraytype=3 memory=1
// CHECK-NEXT:   size=1
// CHECK-NEXT:   size: ok
// CHECK-NEXT:   bounds [] ranges []/0
// CHECK-NEXT:   element none
// CHECK-NEXT:   by_index: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   elements none
// CHECK-NEXT:   iterate: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   top.aa[0] none
// CHECK-NEXT:   by_name: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT: top.nested type=vpiRegArray arraytype=4 memory=0
// CHECK-NEXT:   size=-1
// CHECK-NEXT:   size: vpiSize of a multidimensional array with a dynamic, queue or associative dimension is not available
// CHECK-NEXT:   bounds [] ranges []/0 [0:1]/2
// CHECK-NEXT:   element none
// CHECK-NEXT:   by_index: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   elements none
// CHECK-NEXT:   iterate: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT:   top.nested[0] none
// CHECK-NEXT:   by_name: elements of a dynamic array, queue or associative array are not available through VPI
// CHECK-NEXT: top.fa type=vpiRegArray arraytype=1 memory=0
// CHECK-NEXT:   size=-1
// CHECK-NEXT:   size: vpiSize of a multidimensional array with a dynamic, queue or associative dimension is not available
// CHECK-NEXT:   bounds [0:1] ranges [0:1]/2 []/0
// CHECK-NEXT:   element found
// CHECK-NEXT:   by_index: ok
// CHECK-NEXT:   [1] type=vpiRegArray arraytype=2 size=4
// CHECK-NEXT:   bounds [0:3] ranges [0:3]/4
// CHECK-NEXT: top.dyn size=5
// CHECK-NEXT:   bounds [0:4] ranges [0:4]/5
// CHECK-NEXT: top.q size=0
// CHECK-NEXT:   bounds [] ranges []/0
// CHECK-NEXT: top.aa size=2
// CHECK-NEXT:   bounds [] ranges []/0
// CHECK-NEXT: kept dyn range [0:4]/5
