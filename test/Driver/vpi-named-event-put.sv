// RUN: %target_clang %target_pic -c %S/Inputs/vpi-named-event-put.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O3 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 38.34: vpi_put_value on a named event toggles it and ignores
// value_p, which may be NULL. A value used to be decoded as event storage and
// crash; NULL was refused. Delayed puts stay unsupported and do not trigger.
module top;
  event e, ea [2];
  int hits, element_hits;
  always @(e) hits++;
  always @(ea[1]) element_hits++;
  import "DPI-C" context function void put_null();
  import "DPI-C" context function void put_int();
  import "DPI-C" context function void put_element();
  import "DPI-C" context function void put_delayed();
  initial begin
    #1 put_null();
    #1 $display("hits=%0d", hits);
    put_int();
    #1 $display("hits=%0d", hits);
    put_element();
    #1 $display("element_hits=%0d", element_hits);
    put_delayed();
    #2 $display("hits=%0d", hits);
  end
endmodule

// CHECK: null error=none
// CHECK-NEXT: hits=1
// CHECK-NEXT: int error=none
// CHECK-NEXT: hits=2
// CHECK-NEXT: element error=none
// CHECK-NEXT: element_hits=1
// CHECK-NEXT: delayed error=delayed VPI writes are not supported
// CHECK-NEXT: hits=2
