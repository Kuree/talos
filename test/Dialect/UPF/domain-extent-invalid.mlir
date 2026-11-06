// RUN: talos-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{extent boundary must be a nonempty instance path}}
#bad = #upf.extent<included = [""], excluded = []>
module {}

// -----

// expected-error @+1 {{extent boundary must be a nonempty instance path}}
#bad = #upf.extent<included = [1 : i32], excluded = []>
module {}

// -----

// expected-error @+1 {{extent boundary must be unique}}
#bad = #upf.extent<included = ["top.a"], excluded = ["top.a"]>
module {}

// -----

// expected-error @+1 {{extent boundaries must alternate inclusion and exclusion}}
#bad = #upf.extent<included = [], excluded = ["top.a"]>
module {}

// -----

// expected-error @+1 {{extent boundaries must alternate inclusion and exclusion}}
#bad = #upf.extent<included = ["top.a", "top.a.b"], excluded = []>
module {}

// -----

// expected-error @+1 {{extent boundaries must alternate inclusion and exclusion}}
#bad = #upf.extent<included = ["top.a"], excluded = ["top.a.b", "top.a.b.c"]>
module {}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // expected-error @+1 {{domain element must not be empty}}
  upf.domain @Invalid elements ["top.a"] power @rail on [] {excluded_elements = [""]}
}
