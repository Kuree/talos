// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=NATIVE
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' | FileCheck %s --check-prefix=BYTECODE

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @queue_mutation {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.process"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.take"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.read_then_insert"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.append"
    simulation.func @process(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %queue: !simulation.queue<i64, 4>
            {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 1 : i32} {
      %index = arith.constant 1 : i64
      %value = arith.constant 42 : i64
      simulation.queue.insert %value into %queue[%index] :
          !simulation.queue<i64, 4>, i64
      simulation.queue.delete %queue[%index] : !simulation.queue<i64, 4>
      simulation.return
    }
    simulation.func @take(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !simulation.queue<i64, 4> {simulation.capture_kind = 2 : i32}, %i: i64 {simulation.capture_kind = 2 : i32}) -> i64
        attributes {code_unit_id = 2 : i64, entry_kind = 8 : i32} {
      %old = simulation.queue.pop %q[%i] : !simulation.queue<i64, 4> -> i64
      simulation.return %old : i64
    }
    simulation.func @append(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !simulation.queue<i64, 0> {simulation.capture_kind = 2 : i32}, %v: i64 {simulation.capture_kind = 2 : i32}) attributes {code_unit_id = 4 : i64, entry_kind = 8 : i32} {
      simulation.queue.push_back %v into %q : !simulation.queue<i64, 0>, i64
      simulation.return
    }
    simulation.func @read_then_insert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !simulation.queue<i64, 4> {simulation.capture_kind = 2 : i32}, %i: i64 {simulation.capture_kind = 2 : i32}) -> i64
        attributes {code_unit_id = 3 : i64, entry_kind = 8 : i32} {
      %old = simulation.container.read %q, %i : (!simulation.queue<i64, 4>, i64) -> i64
      simulation.queue.insert %old into %q[%i] : !simulation.queue<i64, 4>, i64
      simulation.queue.delete %q[%i] : !simulation.queue<i64, 4>
      simulation.return %old : i64
    }
  }
}

// NATIVE-DAG: llvm.func @talos_rt_v1_queue_insert
// NATIVE-DAG: llvm.func @talos_rt_v1_queue_delete_index
// NATIVE-LABEL: llvm.func @process(
// NATIVE: llvm.call @talos_rt_v1_queue_insert
// NATIVE: llvm.call @talos_rt_v1_queue_delete_index
// NATIVE-NOT: simulation.queue
// NATIVE-LABEL: llvm.func @take(
// NATIVE: llvm.call @talos_rt_v1_queue_read_delete_checked
// NATIVE-NOT: llvm.call @talos_rt_v1_queue_delete_index
// NATIVE-LABEL: llvm.func @append(
// NATIVE-NOT: llvm.call @talos_rt_v1_container_size
// NATIVE: llvm.call @talos_rt_v1_queue_push(
// NATIVE-LABEL: llvm.func @read_then_insert(
// NATIVE: llvm.call @talos_rt_v1_container_read_checked
// NATIVE: llvm.call @talos_rt_v1_queue_insert
// NATIVE: llvm.call @talos_rt_v1_queue_delete_index

// Queue insert (0x00010445) and queue delete (0x00010444) are encoded in
// program order in the bytecode image.
// BYTECODE: runtime.bytecode_image = array<i8: {{.*}}69, 4, 1, 0{{.*}}68, 4, 1, 0
// BYTECODE: runtime.bytecode_function = 0 : i32
