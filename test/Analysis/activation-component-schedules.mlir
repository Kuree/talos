// RUN: talos-opt %S/activation-publication-feedback.mlir --test-talos-activation-regions='functions=a,b components=true reaching-values=true' -o %t.after 2>&1 | FileCheck %s
// RUN: talos-opt %S/activation-publication-feedback.mlir -o %t.before
// RUN: diff %t.before %t.after
// RUN: talos-opt %S/activation-regions.mlir --test-talos-activation-regions='functions=unbounded components=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=UNAVAILABLE
// RUN: talos-opt %S/../Conversion/simulation-statement-fusion-snapshot.mlir --test-talos-activation-regions='functions=producer_and_consumer,transform components=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SNAPSHOT
// A cycle is a supported schedule, rather than an unavailable analysis. The
// SCC stays local and the two original sensitivity events remain distinct.
// CHECK: region components: valid nodes=8 components=8 cyclic=0 events=2
// CHECK-NEXT: source=6
// CHECK-NEXT: ssa=6
// CHECK: slice components: valid nodes=2 components=2 cyclic=0 events=2
// CHECK: region components: valid nodes=13 components=8 cyclic=1 events=2
// CHECK: slice components: valid nodes=2 components=1 cyclic=1 events=2
// UNAVAILABLE: region components: unsupported
// UNAVAILABLE-NEXT: slice components: unsupported
// SNAPSHOT: region components: valid nodes=21 components=14 cyclic=1 events=2
// SNAPSHOT: snapshot=2
// SNAPSHOT: slice components: valid nodes=4 components=4 cyclic=0 events=2
// CHECK: region components: valid nodes=12 components=9 cyclic=1 events=2
// CHECK: slice components: valid nodes=2 components=1 cyclic=1 events=2
