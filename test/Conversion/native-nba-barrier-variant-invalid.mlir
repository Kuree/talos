// RUN: talos-opt %s --materialize-native-eval-routes --verify-diagnostics

// The fast two-state NBA barrier is specialized to the NBA region; a call
// for any other region would run that specialization in the wrong region.
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  llvm.func @__talos_aot_static_nba_commit_v1(%ctx: !llvm.ptr, %frame: !llvm.ptr, %region: i32, %out: !llvm.ptr) -> i32 {
    llvm.return %region : i32
  }
  llvm.func @__talos_aot_static_nba_commit_two_state_fast_v1(!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
  llvm.func @dispatch(%ctx: !llvm.ptr, %frame: !llvm.ptr, %out: !llvm.ptr, %region: i32) -> i32 {
    // expected-error @below {{a fast two-state NBA barrier runs only in the NBA region}}
    %r = llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1(%ctx, %frame, %region, %out) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr) -> i32
    llvm.return %r : i32
  }
}
