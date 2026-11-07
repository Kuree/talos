// RUN: talos-opt %s --normalize-upf-equivalences --resolve-upf-domains --canonicalize --cse --verify-each | talos-opt --normalize-upf-equivalences --verify-each | FileCheck %s
// RUN: talos-opt %s --elaborate-upf --canonicalize --cse --verify-each | FileCheck %s --check-prefix=LOWER --implicit-check-not=upf. --implicit-check-not=simulation.power. --implicit-check-not=simulation.spawn
// Full I can be transitive through a set association. Supplied roots and local
// identities remain distinct, and empty containers add no simulation actors.
#fa = {power = @ra, ground = @g, nwell = @na, pwell = @g, deepnwell = @g, deeppwell = @g}
#fb = {power = @rb, ground = @g, nwell = @nb, pwell = @g, deepnwell = @g, deeppwell = @g}
module {
  // CHECK: upf.supply @ra names ["/top/PA"] writable = true
  upf.supply @ra names ["/top/PA"] writable = true
  // CHECK: upf.supply @rb names ["/top/PB"] writable = true
  upf.supply @rb names ["/top/PB"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply @na names ["/top/NA"] writable = true
  upf.supply @nb names ["/top/NB"] writable = true
  // CHECK: upf.supply_set @p functions {{.*}}power = @ra
  upf.supply_set @p functions #fa required ["power", "ground"] {owner = @P, materialized_functions = ["power", "ground", "nwell"]}
  // CHECK: upf.supply_set @q functions {{.*}}power = @rb
  upf.supply_set @q functions #fb required ["power", "ground"] {owner = @Q, associated = [@alias], materialized_functions = ["power", "ground", "nwell"]}
  upf.supply_set @alias functions #fb required ["power", "ground"] {associated = [@q], materialized_functions = ["power", "ground", "nwell"]}
  upf.supply_set @c functions #fa required ["power", "ground"] {owner = @C}
  upf.supply_set @outer functions #fa required ["power", "ground"] {owner = @Outer}
  upf.equivalent [@p, @alias] kind interchangeable
  upf.domain @P elements [] power @ra on [] {primary = @p, ground = @g}
  upf.domain @Q elements [] power @rb on [] {primary = @q, ground = @g, policies = [@q, @alias]}
  // CHECK: upf.composite_domain @C subdomains [@P, @Q] primary @c
  upf.composite_domain @C subdomains [@P, @Q] primary @c
  // CHECK: upf.composite_domain @Outer subdomains [@C] primary @outer
  upf.composite_domain @Outer subdomains [@C] primary @outer
  // LOWER: simulation.design @empty_functional_composite
  simulation.design @empty_functional_composite {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}
