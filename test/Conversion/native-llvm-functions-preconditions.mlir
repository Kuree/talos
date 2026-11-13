// RUN: talos-opt %s --split-input-file --verify-diagnostics --prepare-native-llvm-functions

// LLVM function preparation starts only where native materialization ended.

// expected-error @below {{LLVM coroutine conversion requires the native preparation pipeline}}
module {
}

// -----

// expected-error @below {{LLVM coroutine conversion requires a target layout}}
module attributes {native.processes_materialized} {
}

