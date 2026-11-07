// RUN: talos-opt %s --split-input-file --normalize-upf-equivalences --verify-diagnostics
// RUN: talos-opt %s --split-input-file --resolve-upf-domains --verify-diagnostics
// Global semantic validation also runs without equivalence declarations or
// physical domains, before any root merge, ownership mutation or allocation.
#fa = {power = @a, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g}
#fb = {power = @b, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g}
module {
  upf.supply @a names ["/top/A"] writable = true
  upf.supply @b names ["/top/B"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply_set @ca functions #fa required ["power", "ground"] {owner = @CA}
  upf.supply_set @cb functions #fb required ["power", "ground"] {owner = @CB}
  // expected-error @+1 {{composite and subdomain primaries must be electrically equivalent or functionally equivalent and interchangeable}}
  upf.composite_domain @CA subdomains [@CB] primary @ca
  upf.composite_domain @CB subdomains [] primary @cb
}
// -----
#fa = {power = @a, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g}
#fb = {power = @b, ground = @g, nwell = @g, pwell = @g, deepnwell = @g, deeppwell = @g}
module {
  upf.supply @a names ["/top/A"] writable = true
  upf.supply @b names ["/top/B"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply_set @ca functions #fa required ["power", "ground"] {owner = @CA}
  upf.supply_set @cb functions #fb required ["power", "ground"] {owner = @CB}
  upf.equivalent [@ca, @cb] kind functional
  // expected-error @+1 {{composite and subdomain primaries must be electrically equivalent or functionally equivalent and interchangeable}}
  upf.composite_domain @CA subdomains [@CB] primary @ca
  upf.composite_domain @CB subdomains [] primary @cb
}
// -----
#fa = {power = @a, ground = @g, nwell = @na, pwell = @g, deepnwell = @g, deeppwell = @g}
#fb = {power = @b, ground = @g, nwell = @nb, pwell = @g, deepnwell = @g, deeppwell = @g}
module {
  upf.supply @a names ["/top/A"] writable = true
  upf.supply @b names ["/top/B"] writable = true
  upf.supply @g names ["/top/G"] writable = true
  upf.supply @na names ["/top/NA"] writable = true
  upf.supply @nb names ["/top/NB"] writable = true
  upf.supply_set @ca functions #fa required ["power", "ground", "nwell"] {owner = @CA}
  upf.supply_set @cb functions #fb required ["power", "ground", "nwell"] {owner = @CB}
  upf.equivalent [@a, @b] kind interchangeable
  // expected-error @+1 {{composite and subdomain primaries must be electrically equivalent or functionally equivalent and interchangeable}}
  upf.composite_domain @CA subdomains [@CB] primary @ca
  upf.composite_domain @CB subdomains [] primary @cb
}
// -----
#f = {power = @a, ground = @a, nwell = @a, pwell = @a, deepnwell = @a, deeppwell = @a}
module {
  upf.supply @a names ["/top/A"] writable = true
  upf.supply_set @ca functions #f required ["power", "ground"] {owner = @CA}
  upf.supply_set @cb functions #f required ["power", "ground"] {owner = @CB}
  // expected-error @+1 {{cycle in composite domain composition}}
  upf.composite_domain @CA subdomains [@CB] primary @ca
  upf.composite_domain @CB subdomains [@CA] primary @cb
}
