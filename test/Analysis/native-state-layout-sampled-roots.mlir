// RUN: talos-opt %s --test-talos-native-state-layout-analysis -o /dev/null 2>&1 | FileCheck %s

// The physical order is chosen independently of the static handle IDs. A
// net and a variable may have the same descriptor number in their namespaces.
module attributes {native.sampled_placement = array<i64: 2, 0, 1, 1>} {
  simulation.design @sampled_layout {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i64 design
    simulation.storage.decl 1 in 0 : !simulation.logic<5> design
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.storage.decl 2 in 0 : i16 design
  }
}
// CHECK: bound 1 offset=64 width=64
// CHECK-NEXT: bound 2 offset=8 width=5
// CHECK-NEXT: bound 3 offset=0 width=1
// CHECK-NEXT: bound 4 offset=128 width=16
