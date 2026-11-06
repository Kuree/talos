// RUN: talos-opt %s --prepare-upf-snapshot-publications --verify-each | FileCheck %s --implicit-check-not=simulation.snapshot_publications
// The outer module pass resolves and examines its own UPF declarations.
// Nested module declarations have their own pass scope and optional extents.
module {
  // CHECK: module @nested
  module @nested {
    upf.supply @rail names ["/top/VDD"] writable = true
    // CHECK: upf.domain @Nested elements ["top.a"]
    upf.domain @Nested elements ["top.a"] power @rail on []
  }
}
