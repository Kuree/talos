// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each | FileCheck %s --implicit-check-not=upf.composite_domain --implicit-check-not=.epoch --implicit-check-not=simulation.power.
// A container over empty physical extents creates no monitor or corruption
// machinery; only the existing supply-root initialization remains executable.
#f = {power = @r, ground = @g, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply_set @p functions #f required ["power", "ground"] {owner = @P}
  upf.supply_set @c functions #f required ["power", "ground"] {owner = @C}
  upf.domain @P elements [] power @r on [] {primary = @p, ground = @g}
  upf.composite_domain @C subdomains [@P] primary @c
  // CHECK: simulation.design @empty_composite
  simulation.design @empty_composite {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    // CHECK: simulation.func @root
    // CHECK-NOT: simulation.spawn
    // CHECK: simulation.return
    // CHECK-NOT: simulation.func
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}
