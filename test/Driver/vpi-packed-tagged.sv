// RUN: %target_clang %target_pic -c %S/Inputs/vpi-packed-tagged.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O0 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 37.25-37.26: struct and union typespecs, variables and nets
// answer vpiPacked and vpiTagged. Only a tagged union is tagged (7.3.2); a
// struct answers FALSE rather than vpiUndefined, which C would read as TRUE.
module top;
  typedef struct { int a; byte b; } unpacked_t;
  typedef struct packed { logic [1:0] hi; logic [3:0] lo; } packed_t;
  typedef union packed { logic [7:0] w; logic [7:0] u; } packed_union_t;
  typedef union tagged { int i; real r; } tagged_t;
  typedef union tagged packed { logic [3:0] a; logic [3:0] b; } tagged_net_t;
  unpacked_t su = '{1, 2};
  packed_t sp = '{1, 11};
  packed_union_t un = 8'h42;
  tagged_t ta = tagged i 4;
  wire packed_t sn = '{2, 3};
  wire tagged_net_t tn;
  import "DPI-C" context function void probe();
  initial #1 probe();
endmodule

// CHECK: top.su vpiStructVar packed=0 tagged=0 vpiStructTypespec packed=0 tagged=0
// CHECK-NEXT: top.sp vpiStructVar packed=1 tagged=0 vpiStructTypespec packed=1 tagged=0
// CHECK-NEXT: top.un vpiUnionVar packed=1 tagged=0 vpiUnionTypespec packed=1 tagged=0
// CHECK-NEXT: top.ta vpiUnionVar packed=0 tagged=1 vpiUnionTypespec packed=0 tagged=1
// CHECK-NEXT: top.sn vpiStructNet packed=1 tagged=0 vpiStructTypespec packed=1 tagged=0
// CHECK-NEXT: top.tn vpiUnionNet packed=1 tagged=1 vpiUnionTypespec packed=1 tagged=1
