// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-mark-contribution-mirrors{vpi=off}))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-mark-contribution-mirrors{vpi=full}))' | FileCheck %s --check-prefix=WRITABLE
// RUN: not talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-mark-contribution-mirrors{vpi=write}))' 2>&1 | FileCheck %s --check-prefix=INVALID
// INVALID: error: invalid VPI contribution mirror contract

// IEEE 1800-2023 6.5, 6.6.1 Table 6-2, 28.12.1: a lone strong contribution
// to a wire bit, met only by the z of undriven sources, resolves to its own
// value, so its slot equals the net bit. A writable VPI client can force any
// net and release must then restore the drivers' values (38.34, 10.6.2): it
// records nothing.
// WRITABLE-NOT: contribution_mirrors_net

// Mirrors: the only driver of net 0, the two halves partitioning net 1, and
// the lone sparse driver of net 2. Not: the overlapping drivers of net 3
// (6.6.1 resolves them together), the pull driver of net 4 (28.11), the
// sequential-UDP-style state read of driver 7, the deferred bank drive of
// driver 8, the run-time indexed drive of driver 9, and driver 10, which
// stale bits outside its driven range would show. The run-time indexed drive
// of driver 12 resolves all of net 9 from both slots, so its static sibling
// 11 keeps its slot too. A suspension watching driver 13 samples its slot
// (9.4.2), and a direct write replaces net 11 without driver 14 (6.6.7).
// A stale mark is replaced.
// CHECK-LABEL: simulation.design @mirrors
// CHECK:      simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<8> design {simulation.contribution_mirrors_net}
// CHECK-NEXT: simulation.driver.decl 1 in 0 drives 1 : !simulation.logic<8> design {driven_low = 0 : i64, driven_width = 4 : i64, simulation.contribution_mirrors_net}
// CHECK-NEXT: simulation.driver.decl 2 in 0 drives 1 : !simulation.logic<8> design {driven_low = 4 : i64, driven_width = 4 : i64, simulation.contribution_mirrors_net}
// CHECK-NEXT: simulation.driver.decl 3 in 0 drives 2 : !simulation.logic<8> design {driven_low = 2 : i64, driven_width = 1 : i64, simulation.contribution_mirrors_net}
// CHECK-NEXT: simulation.driver.decl 4 in 0 drives 3 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 5 in 0 drives 3 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 6 in 0 drives 4 : !simulation.logic<8> design {strength0 = 5 : i32, strength1 = 5 : i32}
// CHECK-NEXT: simulation.driver.decl 7 in 0 drives 5 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 8 in 0 drives 6 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 9 in 0 drives 7 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 10 in 0 drives 8 : !simulation.logic<8> design {driven_low = 0 : i64, driven_width = 4 : i64}
// CHECK-NEXT: simulation.driver.decl 11 in 0 drives 9 : !simulation.logic<8> design {driven_low = 0 : i64, driven_width = 4 : i64}
// CHECK-NEXT: simulation.driver.decl 12 in 0 drives 9 : !simulation.logic<8> design {driven_low = 4 : i64, driven_width = 4 : i64}
// CHECK-NEXT: simulation.driver.decl 13 in 0 drives 10 : !simulation.logic<8> design{{$}}
// CHECK-NEXT: simulation.driver.decl 14 in 0 drives 11 : !simulation.logic<8> design{{$}}

!c = !simulation.context
!l4 = !simulation.logic<4>
!l1 = !simulation.logic<1>
!l8 = !simulation.logic<8>
!d1 = !simulation.driver<!l1>
!d4 = !simulation.driver<!l4>
!d8 = !simulation.driver<!l8>
module {
  simulation.design @mirrors {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l8 design
    simulation.net.decl 1 in 0 : !l8 design
    simulation.net.decl 2 in 0 : !l8 design
    simulation.net.decl 3 in 0 : !l8 design
    simulation.net.decl 4 in 0 : !l8 design
    simulation.net.decl 5 in 0 : !l8 design
    simulation.net.decl 6 in 0 : !l8 design
    simulation.net.decl 7 in 0 : !l8 design
    simulation.net.decl 8 in 0 : !l8 design
    simulation.net.decl 9 in 0 : !l8 design
    simulation.net.decl 10 in 0 : !l8 design
    simulation.net.decl 11 in 0 : !l8 design
    simulation.driver.decl 0 in 0 drives 0 : !l8 design
    simulation.driver.decl 1 in 0 drives 1 : !l8 design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.driver.decl 2 in 0 drives 1 : !l8 design {driven_low = 4 : i64, driven_width = 4 : i64}
    simulation.driver.decl 3 in 0 drives 2 : !l8 design {driven_low = 2 : i64, driven_width = 1 : i64}
    simulation.driver.decl 4 in 0 drives 3 : !l8 design {simulation.contribution_mirrors_net}
    simulation.driver.decl 5 in 0 drives 3 : !l8 design
    simulation.driver.decl 6 in 0 drives 4 : !l8 design {strength0 = 5 : i32, strength1 = 5 : i32}
    simulation.driver.decl 7 in 0 drives 5 : !l8 design
    simulation.driver.decl 8 in 0 drives 6 : !l8 design
    simulation.driver.decl 9 in 0 drives 7 : !l8 design
    simulation.driver.decl 10 in 0 drives 8 : !l8 design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.driver.decl 11 in 0 drives 9 : !l8 design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.driver.decl 12 in 0 drives 9 : !l8 design {driven_low = 4 : i64, driven_width = 4 : i64}
    simulation.driver.decl 13 in 0 drives 10 : !l8 design
    simulation.driver.decl 14 in 0 drives 11 : !l8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "top.watch"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32},
                           %v8: !l8 {simulation.capture_kind = 2 : i32},
                           %v4: !l4 {simulation.capture_kind = 2 : i32},
                           %v1: !l1 {simulation.capture_kind = 2 : i32},
                           %i: i32 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d0 = simulation.context.driver %ctx[0] : !d8
      simulation.driver.drive %d0 = %v8 : !d8, !l8
      %d1 = simulation.context.driver %ctx[1] : !d8
      %d1lo = simulation.driver.extract %d1 from 0 : !d8 -> !d4
      simulation.driver.drive %d1lo = %v4 : !d4, !l4
      %d2 = simulation.context.driver %ctx[2] : !d8
      %d2hi = simulation.driver.extract %d2 from 4 : !d8 -> !d4
      %changed = simulation.driver.drive_changed %d2hi = %v4 : !d4, !l4
      %d3 = simulation.context.driver %ctx[3] : !d8
      %d3b = simulation.driver.extract %d3 from 2 : !d8 -> !d1
      simulation.driver.drive %d3b = %v1 : !d1, !l1
      %d4 = simulation.context.driver %ctx[4] : !d8
      simulation.driver.drive %d4 = %v8 : !d8, !l8
      %d5 = simulation.context.driver %ctx[5] : !d8
      simulation.driver.drive %d5 = %v8 : !d8, !l8
      %d6 = simulation.context.driver %ctx[6] : !d8
      simulation.driver.drive %d6 = %v8 : !d8, !l8
      %d7 = simulation.context.driver %ctx[7] : !d8
      %state = simulation.driver.read %d7 : !d8 -> !l8
      simulation.driver.drive %d7 = %state : !d8, !l8
      %d8 = simulation.context.driver %ctx[8] : !d8
      simulation.driver.drive %d8 = %v8 {schedule.defer_net_resolution} : !d8, !l8
      %d9 = simulation.context.driver %ctx[9] : !d8
      %d9i = simulation.driver.dyn_extract %d9 from %i : (!d8, i32) -> !d4
      simulation.driver.drive %d9i = %v4 : !d4, !l4
      %d10 = simulation.context.driver %ctx[10] : !d8
      %d10hi = simulation.driver.extract %d10 from 2 : !d8 -> !d4
      simulation.driver.drive %d10hi = %v4 : !d4, !l4
      %d11 = simulation.context.driver %ctx[11] : !d8
      %d11lo = simulation.driver.extract %d11 from 0 : !d8 -> !d4
      simulation.driver.drive %d11lo = %v4 : !d4, !l4
      %d12 = simulation.context.driver %ctx[12] : !d8
      %d12i = simulation.driver.dyn_extract %d12 from %i : (!d8, i32) -> !d4
      simulation.driver.drive %d12i = %v4 : !d4, !l4
      %d14 = simulation.context.driver %ctx[14] : !d8
      simulation.driver.drive %d14 = %v8 : !d8, !l8
      %n11 = simulation.context.net %ctx[11] : !simulation.net<!l8>
      simulation.net.write %n11 = %v8 : !simulation.net<!l8>, !l8
      simulation.return
    }
    simulation.func @watch(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %d13 = simulation.context.driver %ctx[13] : !d8
      cf.br ^body
    ^body:
      simulation.suspend.change %d13 to ^body : !d8
    }
  }
}

// -----

// IEEE 1800-2023 10.6.2: release restores the value of the drivers, which only
// their slots hold while a net is forced. A design with any force, assign or
// release records no mirrors.
// CHECK-LABEL: simulation.design @released
// CHECK-NOT: contribution_mirrors_net

!c = !simulation.context
!l8 = !simulation.logic<8>
!d8 = !simulation.driver<!l8>
module {
  simulation.design @released {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l8 design
    simulation.net.decl 1 in 0 : !l8 design
    simulation.driver.decl 0 in 0 drives 0 : !l8 design
    simulation.driver.decl 1 in 0 drives 1 : !l8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32},
                           %v8: !l8 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d0 = simulation.context.driver %ctx[0] : !d8
      simulation.driver.drive %d0 = %v8 : !d8, !l8
      %d1 = simulation.context.driver %ctx[1] : !d8
      simulation.driver.drive %d1 = %v8 : !d8, !l8
      %n1 = simulation.context.net %ctx[1] : !simulation.net<!l8>
      simulation.release_override %n1 assign false : !simulation.net<!l8>
      simulation.return
    }
  }
}

// -----

// A drive whose driver cannot be identified may target any driver: no
// mirrors. Here one drive takes either of two drivers from a branch.
// CHECK-LABEL: simulation.design @unknown
// CHECK-NOT: contribution_mirrors_net

!c = !simulation.context
!l8 = !simulation.logic<8>
!d8 = !simulation.driver<!l8>
module {
  simulation.design @unknown {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l8 design
    simulation.net.decl 1 in 0 : !l8 design
    simulation.driver.decl 0 in 0 drives 0 : !l8 design
    simulation.driver.decl 1 in 0 drives 1 : !l8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @drive(%ctx: !c {simulation.capture_kind = 0 : i32},
                           %v8: !l8 {simulation.capture_kind = 2 : i32},
                           %c: i1 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d0 = simulation.context.driver %ctx[0] : !d8
      %d1 = simulation.context.driver %ctx[1] : !d8
      cf.cond_br %c, ^bb1(%d0 : !d8), ^bb1(%d1 : !d8)
    ^bb1(%d: !d8):
      simulation.driver.drive %d = %v8 : !d8, !l8
      simulation.return
    }
  }
}
