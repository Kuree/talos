// RUN: %talos --two-state -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// Under --two-state, a wildcard pattern keeps the z (?) bits of its literal
// operands even when other operands are evaluated at run time (IEEE 1800-2023
// 11.4.6, 12.5.1), and every conversion resizes a composed pattern as it
// resizes the value: by its operand's signedness (6.24.1, 11.8.2).
module m(input logic [3:0] c, input logic [1:0] v, input logic signed [7:0] s,
         input int x, output logic e, output logic [1:0] o, output logic [1:0] p,
         output logic r);
  always_comb begin
    e = c ==? {v, 2'b??};
    // A real item has no pattern bits and keeps the ordinary comparison.
    r = x inside {2.0};
    casez (c)
      4'({4'b1111, 4'b??10}): o = 2'd1;
      default: o = 2'd0;
    endcase
    casez (s)
      signed'({1'b1, 3'b???}): p = 2'd1;
      default: p = 2'd0;
    endcase
  end
endmodule

// The run-time operand {v, 2'b??} is masked like the selector: 0b1100 = -4.
// CHECK: %[[V:.*]] = simulation.packed.flatten {{.*}} -> i2
// CHECK: %[[RHS:.*]] = arith.shli
// CHECK: %[[C:.*]] = simulation.packed.flatten {{.*}} -> i4
// CHECK: %[[MASK:.*]] = arith.constant {simulation.rematerialized} -4 : i4
// CHECK: %[[LHS:.*]] = arith.andi %[[C]], %[[MASK]] : i4
// CHECK: %[[MASK2:.*]] = arith.constant {simulation.rematerialized} -4 : i4
// CHECK: %[[PAT:.*]] = arith.andi %[[RHS]], %[[MASK2]] : i4
// CHECK: arith.cmpi eq, %[[LHS]], %[[PAT]] : i4
// The 4-bit cast keeps ??10: mask 0b0011, bits 0b0010.
// CHECK: %[[C2:.*]] = simulation.packed.flatten {{.*}} -> i4
// CHECK: %[[CASTMASK:.*]] = arith.constant {simulation.rematerialized} 3 : i4
// CHECK: %[[ITEM:.*]] = arith.andi %[[C2]], %[[CASTMASK]] : i4
// CHECK: %[[CASTBITS:.*]] = arith.constant {simulation.rematerialized} 2 : i4
// CHECK: arith.cmpi eq, %[[ITEM]], %[[CASTBITS]] : i4
// The signed cast sign-extends 1??? to 1111_1???: mask and bits 0xf8 = -8.
// CHECK: %[[S:.*]] = simulation.packed.flatten {{.*}} -> i8
// CHECK: %[[SMASK:.*]] = arith.constant {simulation.rematerialized} -8 : i8
// CHECK: %[[SITEM:.*]] = arith.andi %[[S]], %[[SMASK]] : i8
// CHECK: %[[SBITS:.*]] = arith.constant {simulation.rematerialized} -8 : i8
// CHECK: arith.cmpi eq, %[[SITEM]], %[[SBITS]] : i8
