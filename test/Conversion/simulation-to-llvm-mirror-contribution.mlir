// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines --cse | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' --test-talos-print-bytecode=state=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=IMAGE

// IEEE 1800-2023 6.5, 6.6.1 Table 6-2, 28.12.1: the lone strong contribution
// to a wire bit is that bit's value. A driver marked `contribution_mirrors_net` keeps that
// fact, so native drives skip its slot (nets at bytes 0-2, slots at 3-5) and
// the image tells the runtime to read the net instead (flag bit 15).

// The mirror drive stores only its net bit (byte 0), in both planes.
// CHECK-LABEL: llvm.func @mirror(
// CHECK: %[[NV:.*]] = llvm.mlir.addressof @__talos_state_value
// CHECK: %[[NU:.*]] = llvm.mlir.addressof @__talos_state_unknown
// CHECK: llvm.store %{{.*}}, %[[NV]]
// CHECK: llvm.store %{{.*}}, %[[NU]]
// CHECK-NOT: llvm.store
// CHECK: llvm.return

// An unmarked drive stores its slot (byte 4), then the net.
// CHECK-LABEL: llvm.func @plain(
// CHECK: %[[SV:.*]] = llvm.getelementptr %{{.*}}[4]
// CHECK: llvm.store %{{.*}}, %[[SV]]
// CHECK: %[[SU:.*]] = llvm.getelementptr %{{.*}}[4]
// CHECK: llvm.store %{{.*}}, %[[SU]]
// CHECK-COUNT-2: llvm.store
// CHECK-NOT: llvm.store
// CHECK: llvm.return

// The mark is re-proved on the native IR: this sequential-UDP-style body
// reads its own slot, so the drive keeps storing it (byte 5).
// CHECK-LABEL: llvm.func @state(
// CHECK: %[[SV:.*]] = llvm.getelementptr %{{.*}}[5]
// CHECK: llvm.store %{{.*}}, %[[SV]]
// CHECK: llvm.return

// The image flag follows the declaration, a superset of the drivers native
// code elides: the runtime reads driver 2's net although its slot is stored.
// IMAGE: state 3: kind=driver flags=33721 value=27 target=3 width=1
// IMAGE: state 4: kind=driver flags=953 value=35 target=11 width=1
// IMAGE: state 5: kind=driver flags=33721 value=43 target=19 width=1

!c = !simulation.context
!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!d1 = !simulation.driver<!l1>
!d8 = !simulation.driver<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @mirrors {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.g"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.h"
    simulation.net.decl 0 in 0 : !l8 design
    simulation.net.decl 1 in 0 : !l8 design
    simulation.net.decl 2 in 0 : !l8 design
    simulation.driver.decl 0 in 0 drives 0 : !l8 design {driven_low = 3 : i64, driven_width = 1 : i64, simulation.contribution_mirrors_net}
    simulation.driver.decl 1 in 0 drives 1 : !l8 design {driven_low = 3 : i64, driven_width = 1 : i64}
    simulation.driver.decl 2 in 0 drives 2 : !l8 design {driven_low = 3 : i64, driven_width = 1 : i64, simulation.contribution_mirrors_net}
    simulation.func @mirror(%ctx: !c {simulation.capture_kind = 0 : i32},
                            %v: !l1 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !d8
      %b = simulation.driver.extract %d from 3 : !d8 -> !d1
      simulation.driver.drive %b = %v : !d1, !l1
      simulation.return
    }
    simulation.func @plain(%ctx: !c {simulation.capture_kind = 0 : i32},
                           %v: !l1 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %d = simulation.context.driver %ctx[1] : !d8
      %b = simulation.driver.extract %d from 3 : !d8 -> !d1
      simulation.driver.drive %b = %v : !d1, !l1
      simulation.return
    }
    simulation.func @state(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %d = simulation.context.driver %ctx[2] : !d8
      %b = simulation.driver.extract %d from 3 : !d8 -> !d1
      %old = simulation.driver.read %b : !d1 -> !l1
      simulation.driver.drive %b = %old : !d1, !l1
      simulation.return
    }
  }
}
