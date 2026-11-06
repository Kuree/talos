// RUN: talos-opt %s --split-input-file --verify-diagnostics
module {
  // expected-error @+1 {{composite subdomain references must be unique}}
  upf.composite_domain @C subdomains [@P, @P] primary @primary
}

// -----

module {
  // expected-error @+1 {{composite primary must reference its own supply-set handle}}
  upf.composite_domain @C subdomains [] primary @missing
}

// -----

#f = {power = @r, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply_set @c functions #f required ["power", "ground"] {owner = @C}
  // expected-error @+1 {{references an unknown composite subdomain}}
  upf.composite_domain @C subdomains [@missing] primary @c
}

// -----

#f = {power = @r, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply_set @a functions #f required ["power", "ground"] {owner = @A}
  upf.supply_set @b functions #f required ["power", "ground"] {owner = @B}
  // expected-error @+1 {{cycle in composite domain composition}}
  upf.composite_domain @A subdomains [@B] primary @a
  upf.composite_domain @B subdomains [@A] primary @b
}

// -----

#f = {power = @r, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
#other = {power = @s, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply @s names ["/top/OTHER"] writable = true
  upf.supply_set @c functions #f required ["power", "ground"] {owner = @C}
  upf.supply_set @p functions #other required ["power", "ground"] {owner = @P}
  upf.domain @P elements [] power @s on [] {primary = @p, ground = @r}
  // expected-error @+1 {{composite and subdomain primary required functions must be electrically equivalent}}
  upf.composite_domain @C subdomains [@P] primary @c
}

// -----

#f = {power = @r, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply_set @c functions #f required ["power", "ground"] {owner = @C}
  upf.domain @P elements [] power @r on []
  // expected-error @+1 {{subdomain requires a resolved primary supply set}}
  upf.composite_domain @C subdomains [@P] primary @c
}

// -----

#f = {power = @r, ground = @r, nwell = @r, pwell = @r, deepnwell = @r, deeppwell = @r}
module {
  upf.supply @r names ["/top/VDD"] writable = true
  upf.supply_set @c functions #f required ["power", "ground"] {owner = @C}
  // expected-error @+1 {{retention strategy requires a physical owning domain}}
  upf.supply_set @bad functions #f required ["power", "ground"] {owner = @C, strategy = "R"}
  upf.composite_domain @C subdomains [] primary @c
}
