// RUN: talos-opt %s --split-input-file --verify-diagnostics | FileCheck %s

// A declaration of a runtime entry names it by its symbol without the
// version prefix, and has the entry's prototype.
// CHECK: llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}
// CHECK: llvm.func @talos_rt_v2_recursive_export_bitstream({{.*}}) -> i32 attributes {native.runtime_entry = #native.runtime_entry<v2_recursive_export_bitstream>}
llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}
llvm.func @talos_rt_v2_recursive_export_bitstream(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64, i32, !llvm.ptr, !llvm.ptr, i64, i64, i32, i32, !llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<v2_recursive_export_bitstream>}

// -----

// expected-error @+1 {{attribute 'native.runtime_entry' declares @talos_rt_v1_scheduler_fail with an incompatible type}}
llvm.func @talos_rt_v1_scheduler_fail(!llvm.ptr, i64) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}

// -----

// expected-error @+1 {{attribute 'native.runtime_entry' names @talos_rt_v1_scheduler_fail but the function is @talos_rt_v1_scheduler_error}}
llvm.func @talos_rt_v1_scheduler_error(!llvm.ptr, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}

// -----

// expected-error @+1 {{attribute 'native.runtime_entry' belongs on an external llvm.func}}
func.func private @talos_rt_v1_scheduler_fail() attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>}

// -----

// expected-error @+1 {{attribute 'native.runtime_entry' belongs on an external llvm.func}}
llvm.func @talos_rt_v1_scheduler_fail(%context: !llvm.ptr, %status: i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_fail>} {
  llvm.return
}

// -----

// expected-error @+1 {{unknown native runtime entry 'no_such_entry'}}
llvm.func @talos_rt_v1_no_such_entry(!llvm.ptr) attributes {native.runtime_entry = #native.runtime_entry<no_such_entry>}
