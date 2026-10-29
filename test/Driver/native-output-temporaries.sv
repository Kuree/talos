// RUN: talos -O0 %s -o %t.o0
// RUN: %t.o0 | FileCheck %s
// RUN: talos -O3 %s -o %t.o3
// RUN: %t.o3 | FileCheck %s
// RUN: talos -O3 --execution-tier=bytecode %s -o %t.bytecode
// RUN: %t.bytecode | FileCheck %s

// Repeated clocked output can reuse its ABI buffers without changing value/X/Z
// sampling, operand order, or bitwise truth tables (LRM 4.6, 11.4.8, 21.2.1).
module native_output_temporaries;
  bit clock = 0;
  int cycle = 0;
  logic [3:0] value;
  always #1 clock = ~clock;
  always @(negedge clock) begin
    case (cycle)
      0: value = 4'b10xz;
      1: value = 4'bz1x0;
      2: value = 4'b1010;
    endcase
    $display("first %0d %b", cycle, value);
    $display("second %0d %b", cycle, ~value);
    if (cycle == 2) $finish;
    cycle++;
  end
endmodule

// CHECK: first 0 10xz
// CHECK-NEXT: second 0 01xx
// CHECK-NEXT: first 1 z1x0
// CHECK-NEXT: second 1 x0x1
// CHECK-NEXT: first 2 1010
// CHECK-NEXT: second 2 0101
