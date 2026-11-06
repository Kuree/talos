// RUN: talos-opt %s --split-input-file --resolve-upf-domains --verify-diagnostics
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-note @+1 {{atomic minimum extent declared here}}
  upf.domain @Atomic elements ["top.a"] power @rail on [] {atomic = true}
  // expected-error @+1 {{cannot partition atomic power domain Atomic at top.a.b}}
  upf.domain @Steal elements ["top.a.b"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-error @+1 {{cannot partition atomic power domain Atomic at top.a.b}}
  upf.domain @Steal elements ["top.a.b"] power @rail on [] {atomic = true}
  // expected-note @+1 {{atomic minimum extent declared here}}
  upf.domain @Atomic elements ["top.a"] power @rail on [] {atomic = true}
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // The ancestor exclusion cannot bypass protection regained by re-entry.
  // expected-note @+1 {{atomic minimum extent declared here}}
  upf.domain @Atomic elements ["top.a", "top.a.hole.back"] power @rail on []
      {atomic = true, excluded_elements = ["top.a.hole"]}
  // expected-error @+1 {{cannot partition atomic power domain Atomic at top.a.hole.back.leaf}}
  upf.domain @Steal elements ["top.a.hole.back.leaf"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-note @+1 {{also explicitly selected by Atomic}}
  upf.domain @Atomic elements ["top.a"] power @rail on [] {atomic = true}
  // expected-error @+1 {{design instance is selected by multiple power domains: top.a}}
  upf.domain @Steal elements ["top.a"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // The first exclusion allows B; B's atomic minimum still protects back.
  // expected-error @+1 {{cannot partition atomic power domain B at top.a.hole.back}}
  upf.domain @A elements ["top.a", "top.a.hole.back"] power @rail on []
      {atomic = true, excluded_elements = ["top.a.hole"]}
  // expected-note @+1 {{atomic minimum extent declared here}}
  upf.domain @B elements ["top.a.hole"] power @rail on [] {atomic = true}
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-note @+1 {{also explicitly selected by A}}
  upf.domain @A elements ["top.a", "top.a.hole.back"] power @rail on []
      {atomic = true, excluded_elements = ["top.a.hole"]}
  // An ancestor hole does not exempt a conflicting claim at explicit re-entry.
  // expected-error @+1 {{design instance is selected by multiple power domains: top.a.hole.back}}
  upf.domain @B elements ["top.a.hole", "top.a.hole.back"] power @rail on []
}
