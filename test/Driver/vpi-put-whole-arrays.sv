// RUN: %target_clang %target_pic -c %S/Inputs/vpi-put-whole-arrays.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O3 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 37.17 detail 11, 37.26 detail 1: vpi_put_value refuses
// objects without a value property, as vpi_get_value does. Whole dynamic
// arrays, queues, associative arrays and class variables are such objects;
// their storage holds a managed reference, which a written value used to
// overwrite.
module top;
  typedef struct { int a; byte b; } record_t;
  class C;
    int x = 6;
  endclass
  int fixed [3] = '{1, 2, 3};
  int dyn [];
  int q [$];
  int aa [string];
  record_t record = '{4, 5};
  C obj = new;
  int plain;
  import "DPI-C" context function void put();
  initial begin
    dyn = new[3];
    q.push_back(7);
    aa["k"] = 2;
    #1 put();
    #1 $display("fixed=%0d dyn=%0d q=%0d aa=%0d record=%0d obj=%0d plain=%0d",
                fixed[2], dyn.size(), q.size(), aa.num(), record.a, obj.x,
                plain);
  end
endmodule

// CHECK: top.fixed: vpi_put_value is not defined for this VPI object
// CHECK-NEXT: top.dyn: vpi_put_value is not defined for this VPI object
// CHECK-NEXT: top.q: vpi_put_value is not defined for this VPI object
// CHECK-NEXT: top.aa: vpi_put_value is not defined for this VPI object
// CHECK-NEXT: top.record: vpi_put_value is not defined for a whole unpacked aggregate
// CHECK-NEXT: top.obj: vpi_put_value is not defined for this VPI object
// CHECK-NEXT: top.plain: written
// CHECK-NEXT: fixed=3 dyn=3 q=1 aa=1 record=4 obj=6 plain=12345
