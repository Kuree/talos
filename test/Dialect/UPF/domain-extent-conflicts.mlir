// RUN: talos-opt %s --split-input-file --resolve-upf-domains --verify-diagnostics
// IEEE 1801-2018 5.7.9: equal explicit claims are errors even when supplies
// coincide. An ancestor exclusion does not cancel a deeper explicit include.
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-note @+1 {{also explicitly selected by First}}
  upf.domain @First elements ["top.a", "top.a"] power @rail on []
  // expected-error @+1 {{design instance is selected by multiple power domains: top.a}}
  upf.domain @Second elements ["top.a"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-note @+1 {{also explicitly selected by First}}
  upf.domain @First elements ["top.a", "top.a.b"] power @rail on []
      {excluded_elements = ["top.a"]}
  // expected-error @+1 {{design instance is selected by multiple power domains: top.a.b}}
  upf.domain @Second elements ["top.a.b"] power @rail on []
}
