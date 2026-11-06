// RUN: talos-opt %s --split-input-file --resolve-upf-domains --canonicalize --cse --verify-each | FileCheck %s
// RUN: talos-opt %s --split-input-file --resolve-upf-domains --resolve-upf-domains --verify-each | FileCheck %s
// IEEE 1801-2018 4.4.2/5.7.2/5.9/6.20: ownership follows resolved
// parents, preserves explicit re-entry, and excludes exact include/exclude
// ties. Resolve again from raw aggregates rather than trusting cached attrs.
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // CHECK: upf.domain @A elements ["top.a", "top.a.b.back", "top.a.keep", "top.a"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a", "top.a.b.back"], excluded = ["top.a.b"]>
  upf.domain @A elements ["top.a", "top.a.b.back", "top.a.keep", "top.a"] power @rail on []
      {excluded_elements = ["top.a.b", "top.unrelated"]}
  // CHECK: upf.domain @B elements ["top.a.b"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a.b"], excluded = ["top.a.b.back", "top.a.b.hole"]>
  upf.domain @B elements ["top.a.b"] power @rail on []
      {excluded_elements = ["top.a.b.hole"]}
  // CHECK: upf.domain @C elements ["top.a$alias"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a$alias"], excluded = []>
  upf.domain @C elements ["top.a$alias"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // CHECK: upf.domain @Empty elements ["top.a", "top.a"]
  // CHECK-SAME: extent = #upf.extent<included = [], excluded = []>
  upf.domain @Empty elements ["top.a", "top.a"] power @rail on []
      {excluded_elements = ["top.a", "top.a", "top.unrelated"]}
  // An excluded explicit claim must not defeat the surviving claim.
  // CHECK: upf.domain @Owner elements ["top.a"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a"], excluded = []>
  upf.domain @Owner elements ["top.a"] power @rail on []
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // CHECK: upf.domain @Stale elements ["top.a"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a"], excluded = []>
  upf.domain @Stale elements ["top.a"] power @rail on []
      {extent = #upf.extent<included = ["stale"], excluded = []>}
}

// -----

module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // CHECK: upf.domain @Parent elements ["top.a"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a"], excluded = ["top.a.b"]>
  upf.domain @Parent elements ["top.a"] power @rail on []
  // CHECK: upf.domain @Child elements ["top.a.b"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a.b"], excluded = ["top.a.b.c"]>
  upf.domain @Child elements ["top.a.b"] power @rail on []
      {excluded_elements = ["top.a.b.c"]}
  // C remains outside both extents: the parent does not regain its grandchild.
}
