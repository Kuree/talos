// RUN: talos-opt %s --prepare-native-schedule-inputs | FileCheck %s --implicit-check-not=__talos_native_vtable_ --implicit-check-not=__talos_synchronous

// An unused class needs no method tables or synchronous task helpers.
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @empty_class {
    simulation.scope.decl 0 hierarchy "top"
    simulation.class.decl @Unused id 1 {
      is_abstract = false, is_final = false, is_interface = false
    }
  }
}

// CHECK: simulation.class.decl @Unused id 1
