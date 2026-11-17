// RUN: talos -emit-sim %s -o - | FileCheck %s

// A blocking store to an indexed part-select of a fixed element writes only
// the in-range bits, and nothing for an X/Z index (IEEE 1800-2023 11.5.1).
// The store is split: once the index is known and the whole selection fits,
// one dynamic reference covers it. That reference selects by the index's
// two-state value, the one the in-range test reads, so range analysis can
// prove it contained in w[0] and the store can be direct.
// CHECK: %[[KNOWN:.+]] = simulation.logic.compare case_eq
// CHECK-NEXT: cf.cond_br %[[KNOWN]], ^[[DISPATCH:bb[0-9]+]],
// CHECK: ^[[DISPATCH]]:
// CHECK: %[[FITS:.+]] = arith.cmpi sle, %[[LOW:[0-9]+]], %{{.+}} : i66
// CHECK-NEXT: cf.cond_br %[[FITS]], ^[[FULL:bb[0-9]+]],
// CHECK: ^[[FULL]]:
// CHECK-NEXT: %[[SELECTED:.+]] = simulation.ref.dyn_extract %{{.+}} from %[[LOW]] : (!simulation.ref<!simulation.packed_array<7 : 0 x !simulation.logic<1>>>, i66)
// CHECK: simulation.ref.store %{{.+}} to %[[SELECTED]]
module part_select_known_index;
  logic [1:0][7:0] w;
  logic [2:0] idx;
  always_comb begin
    w = '0;
    w[0][idx +: 2] = '1;
  end
  initial begin
    idx = 6;
    #1 $display("%h", w);
  end
endmodule
