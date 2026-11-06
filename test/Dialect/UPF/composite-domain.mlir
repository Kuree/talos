// RUN: talos-opt %s --resolve-upf-domains --canonicalize --cse --verify-each | talos-opt --verify-each | FileCheck %s
// Naturally equivalent primaries share corresponding required roots, while
// unused well roots and local catalog/handle identities remain independent.
#f1 = {power = @r, ground = @g, nwell = @n1, pwell = @r, deepnwell = @r, deeppwell = @r}
#f2 = {power = @r, ground = @g, nwell = @n2, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply @n1 names ["/top/N1"] writable = true
  upf.supply @n2 names ["/top/N2"] writable = true
  upf.supply_set @p functions #f1 required ["power", "ground"] {owner = @P}
  upf.supply_set @q functions #f2 required ["ground", "power"] {owner = @Q}
  upf.supply_set @c functions #f1 required ["power", "ground"] {owner = @C}
  upf.supply_set @outer functions #f1 required ["power", "ground"] {owner = @Outer}
  upf.domain @P elements ["top.p"] power @r on [] {primary = @p, ground = @g}
  upf.domain @Q elements ["top.q"] power @r on [] {primary = @q, ground = @g}
  // CHECK: upf.composite_domain @C subdomains [@P, @Q] primary @c
  upf.composite_domain @C subdomains [@P, @Q] primary @c
  // CHECK: upf.composite_domain @Outer subdomains [@C] primary @outer
  upf.composite_domain @Outer subdomains [@C] primary @outer
}
