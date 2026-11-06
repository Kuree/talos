// RUN: talos-opt %s --resolve-upf-domains --canonicalize --cse --verify-each | FileCheck %s
// RUN: talos-opt %s --resolve-upf-domains --resolve-upf-domains --verify-each | FileCheck %s
// IEEE 1801-2018 6.20/8.3.3: atomic minimum ownership within an outer
// non-atomic domain, nested atomic domains with explicit holes, and protected
// re-entry. Each atomic extent must exclude the other's protected subtree.
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  // CHECK: upf.domain @Outer elements ["top.a"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a"], excluded = ["top.a.b"]>
  upf.domain @Outer elements ["top.a"] power @rail on []
  // CHECK: upf.domain @Atomic elements ["top.a.b", "top.a.b.hole.back"]
  // CHECK-SAME: atomic = true
  // CHECK-SAME: extent = #upf.extent<included = ["top.a.b", "top.a.b.hole.back"], excluded = ["top.a.b.hole"]>
  upf.domain @Atomic elements ["top.a.b", "top.a.b.hole.back"] power @rail on []
      {atomic = true, excluded_elements = ["top.a.b.hole"]}
  // CHECK: upf.domain @Hole elements ["top.a.b.hole"]
  // CHECK-SAME: extent = #upf.extent<included = ["top.a.b.hole"], excluded = ["top.a.b.hole.back"]>
  upf.domain @Hole elements ["top.a.b.hole"] power @rail on []
      {atomic = true, excluded_elements = ["top.a.b.hole.back"]}
  // CHECK: upf.domain @Empty elements ["top.a"]
  // CHECK-SAME: atomic = true
  // CHECK-SAME: extent = #upf.extent<included = [], excluded = []>
  upf.domain @Empty elements ["top.a"] power @rail on []
      {atomic = true, excluded_elements = ["top.a"]}
}
