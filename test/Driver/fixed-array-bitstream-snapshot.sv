// RUN: talos -O3 %s -o %t.native && %t.native | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.bytecode && %t.bytecode | FileCheck %s

// IEEE 1800-2023 6.24.3: the leftmost element occupies the high bits.
// A four-state destination retains X/Z, and a bit destination coerces both.
module top;
  typedef logic [3:0] four_t;
  typedef bit [3:0] two_t;
  logic [1:0] ascending [2:3], descending [3:2];

  function automatic four_t pack_then_overwrite(input logic [1:0] snapshot [3:2]);
    descending = '{default: '0};
    return four_t'(snapshot);
  endfunction

  initial begin
    ascending = '{2'b1x, 2'bz0};
    descending = ascending;
    #1;
    $display("asc=%b bits=%b", four_t'(ascending), two_t'(descending));
    $display("snapshot=%b", pack_then_overwrite(descending));
    $display("stored=%b", four_t'(descending));
  end
endmodule
// CHECK: asc=1xz0 bits=1000
// CHECK-NEXT: snapshot=1xz0
// CHECK-NEXT: stored=0000
