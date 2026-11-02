// RUN: %talos -O3 --vpi=off --mlir-timing - -o %t.exe < %S/port-storage-alias.sv 2> %t.log
// RUN: FileCheck %s --input-file=%t.log
// RUN: %t.exe | FileCheck %S/port-storage-alias.sv

// A design the automatic scheduler planned for eval can still fail its closure
// check. The generic scheduler then compiles it from the same inputs, including
// standard input, which cannot be read twice.
// CHECK: note: eval call closure check failed; compiling again with the generic scheduler
// CHECK-NOT: note: eval call closure check failed
