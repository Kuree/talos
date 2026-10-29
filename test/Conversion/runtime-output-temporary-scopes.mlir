// RUN: talos-opt %s --convert-talos-runtime-to-llvm | %llvm_dist/bin/mlir-opt --allow-unregistered-dialect --convert-func-to-llvm | talos-opt --pass-pipeline='builtin.module(llvm.func(talos-native-share-scoped-temporaries))' -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-translate --mlir-to-llvmir %t.mlir | %llvm_dist/bin/opt -passes=verify -disable-output

// Exercise the typed runtime boundary as well as already-lowered LLVM ops.
// The packed value and X/Z planes are both borrowed through the argument array
// until the synchronous output returns (LRM 21.2.1).
// Upstream mlir-opt only carries the in-tree module runtime attributes through
// its function-signature conversion; all operations there are upstream ops.
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8"} {
  // CHECK-LABEL: llvm.func @output
  // CHECK-COUNT-4: llvm.intr.lifetime.start
  // CHECK: llvm.call @talos_rt_v1_eval_display
  // CHECK-COUNT-4: llvm.intr.lifetime.end
  // CHECK-NEXT: llvm.return
  func.func @output(%ctx: !runtime.context, %value: i13, %unknown: i13) {
    %one = llvm.mlir.constant(1 : i32) : i32
    %newline = llvm.mlir.constant(true) : i1
    %fd = runtime.file_descriptor.from_bits %one
    %arg = runtime.argument.packed %value, %unknown
        {is_signed = false} : (i13, i13) -> !runtime.arg
    %args = runtime.argument.array(%arg)
    %env = runtime.format.environment {
      scope = "top", library_cell = "work.top", time_width = 0 : i32,
      time_suffix = "", time_multiplier = 1 : i64
    }
    %status = "runtime.display"(%ctx, %fd, %newline, %args, %env)
        {default_radix = #runtime.radix<binary>, schedule.eval.direct_output} :
        (!runtime.context, !runtime.fd, i1, !runtime.args, !runtime.format_env)
        -> !runtime.status
    return
  }
}
