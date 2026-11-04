// RUN: %talos --two-state -emit-talos %s | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 11.4.12: a concatenation or replication of constants has its
// operands' bits, so the z (?) bits of its literal operands stay do-not-care
// bits of a casez item (12.5.1) or a wildcard equality operand (11.4.6) when
// --two-state projects executable X/Z data to zero.
module m(input logic [15:0] c, output logic [1:0] o, output logic e);
  localparam int Z = 0;
  always_comb begin
    casez (c)
      {3'b000, {1{1'b?}}, {2{5'b?????}}, 2'b10}: o = 2'd1;
      // Fully known nested operands keep their bits.
      {{2{2'b10}}, 4'b????, {1'b0, 1'b1}, {6{1'b?}}}: o = 2'd2;
      default: o = 2'd0;
    endcase
    // 11.4.12.1: a zero-count replication is ignored inside a concatenation.
    e = c ==? {{Z{1'b1}}, {14{1'b?}}, 2'b01};
  end
endmodule

// The first item keeps bits 15:13 and 1:0: 0xe003 = -8189.
// CHECK: %[[C:.*]] = simulation.packed.flatten
// CHECK: %[[MASK0:.*]] = arith.constant {simulation.rematerialized} -8189 : i16
// CHECK: %[[ITEM0:.*]] = arith.andi %[[C]], %[[MASK0]] : i16
// CHECK: %[[BITS0:.*]] = arith.constant {simulation.rematerialized} 2 : i16
// CHECK: arith.cmpi eq, %[[ITEM0]], %[[BITS0]] : i16
// CHECK: %[[E:.*]] = simulation.packed.flatten
// CHECK: %[[MASK2:.*]] = arith.constant {simulation.rematerialized} 3 : i16
// CHECK: %[[WILD:.*]] = arith.andi %[[E]], %[[MASK2]] : i16
// CHECK: %[[BITS2:.*]] = arith.constant {simulation.rematerialized} 1 : i16
// CHECK: arith.cmpi eq, %[[WILD]], %[[BITS2]] : i16
// The second item, tried when the first misses, keeps bits 15:12 = 1010 and
// 7:6 = 01: mask 0xf0c0 = -3904, bits 0xa040 = -24512.
// CHECK: %[[MASK1:.*]] = arith.constant {simulation.rematerialized} -3904 : i16
// CHECK: %[[ITEM1:.*]] = arith.andi %[[C]], %[[MASK1]] : i16
// CHECK: %[[BITS1:.*]] = arith.constant {simulation.rematerialized} -24512 : i16
// CHECK: arith.cmpi eq, %[[ITEM1]], %[[BITS1]] : i16
