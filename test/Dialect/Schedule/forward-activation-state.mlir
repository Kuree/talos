// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(talos-sim-forward-activation-state)' | FileCheck %s

// Within one activation a read of bits the activation wrote or read before
// takes that SSA value; the writes stay (IEEE 1800-2023 4.6, 4.7, 4.9.3). Net
// bits are known from a drive only for contribution mirrors, whose lone strong
// driver determines the net (6.6.1 Table 6-2).

!c = !simulation.context
!l4 = !simulation.logic<4>
!l8 = !simulation.logic<8>
!pa = !simulation.packed_array<1 : 0 x !l4>
!d4 = !simulation.driver<!l4>
!d8 = !simulation.driver<!l8>
!dpa = !simulation.driver<!pa>
!n4 = !simulation.net<!l4>
!n8 = !simulation.net<!l8>
!npa = !simulation.net<!pa>
!r8 = !simulation.ref<i8>
!r16 = !simulation.ref<i16>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @forward attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l8 design
    simulation.net.decl 1 in 0 : !l8 design
    simulation.net.decl 2 in 0 : !pa design
    simulation.net.decl 3 in 0 : !l4 design
    simulation.net.decl 4 in 0 : !l4 design
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i16 design
    simulation.driver.decl 0 in 0 drives 0 : !l8 design {driven_low = 0 : i64, driven_width = 4 : i64, simulation.contribution_mirrors_net}
    simulation.driver.decl 1 in 0 drives 0 : !l8 design {driven_low = 4 : i64, driven_width = 4 : i64, simulation.contribution_mirrors_net}
    simulation.driver.decl 2 in 0 drives 1 : !l8 design
    simulation.driver.decl 3 in 0 drives 1 : !l8 design
    simulation.driver.decl 4 in 0 drives 2 : !pa design {driven_low = 4 : i64, driven_width = 4 : i64, simulation.contribution_mirrors_net}
    // Marked as a mirror only to show that connection alone keeps the net
    // unknown.
    simulation.driver.decl 5 in 0 drives 3 : !l4 design {simulation.contribution_mirrors_net}
    simulation.net.connect.decl 0 in 0 3[0] to 4[0] width 4 reversed = false
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.g"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "top.p"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.s"
    simulation.code_unit.decl 5 in 0 function hierarchy "top.r"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.v"
    simulation.code_unit.decl 7 in 0 function hierarchy "top.d"
    simulation.code_unit.decl 8 in 0 function hierarchy "top.c"
    simulation.code_unit.decl 9 in 0 function hierarchy "top.j"
    simulation.code_unit.decl 10 in 0 function hierarchy "top.e"
    simulation.code_unit.decl 11 in 0 function hierarchy "top.i"

    // The low half is exactly the first mirror drive's value; the whole net is
    // the two drives' values concatenated, most significant first, and a
    // second read takes the same composition.
    // CHECK-LABEL: simulation.func @mirror(
    // CHECK-SAME: %[[LO:[a-z0-9]+]]: !simulation.logic<4> {{.*}}, %[[HI:[a-z0-9]+]]: !simulation.logic<4>
    // CHECK: simulation.driver.drive %{{.*}} = %[[LO]]
    // CHECK: simulation.driver.drive %{{.*}} = %[[HI]]
    // CHECK-NOT: simulation.net.read
    // CHECK: %[[WHOLE:.*]] = simulation.logic.concat %[[HI]], %[[LO]]
    // CHECK: %[[AGAIN:.*]] = simulation.logic.concat %[[HI]], %[[LO]]
    // CHECK-NOT: simulation.net.read
    // CHECK: simulation.return %[[LO]], %[[WHOLE]], %[[AGAIN]]
    simulation.func @mirror(%ctx: !c {simulation.capture_kind = 0 : i32},
                            %lo: !l4 {simulation.capture_kind = 2 : i32},
                            %hi: !l4 {simulation.capture_kind = 2 : i32})
        -> (!l4, !l8, !l8)
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d0 = simulation.context.driver %ctx[0] : !d8
      %d0lo = simulation.driver.extract %d0 from 0 : !d8 -> !d4
      simulation.driver.drive %d0lo = %lo : !d4, !l4
      %d1 = simulation.context.driver %ctx[1] : !d8
      %d1hi = simulation.driver.extract %d1 from 4 : !d8 -> !d4
      simulation.driver.drive %d1hi = %hi : !d4, !l4
      %n0 = simulation.context.net %ctx[0] : !n8
      %n0lo = simulation.net.extract %n0 from 0 : !n8 -> !n4
      %low = simulation.net.read %n0lo : !n4 -> !l4
      %whole = simulation.net.read %n0 : !n8 -> !l8
      %again = simulation.net.read %n0 : !n8 -> !l8
      simulation.return %low, %whole, %again : !l4, !l8, !l8
    }

    // A known subelement of a wider read is forwarded through its extract.
    // CHECK-LABEL: simulation.func @subelement(
    // CHECK-SAME: %[[V:[a-z0-9]+]]: !simulation.logic<4>
    // CHECK-NOT: simulation.net.read
    // CHECK-NOT: simulation.aggregate.extract
    // CHECK: simulation.return %[[V]]
    simulation.func @subelement(%ctx: !c {simulation.capture_kind = 0 : i32},
                                %v: !l4 {simulation.capture_kind = 2 : i32})
        -> !l4 attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %d4 = simulation.context.driver %ctx[4] : !dpa
      %d4hi = simulation.driver.subelement %d4[[1]] : !dpa -> !d4
      simulation.driver.drive %d4hi = %v : !d4, !l4
      %n2 = simulation.context.net %ctx[2] : !npa
      %all = simulation.net.read %n2 : !npa -> !pa
      %high = simulation.aggregate.extract %all[1] : (!pa) -> !l4
      simulation.return %high : !l4
    }

    // A drive of a net with several drivers resolves them together; its bits
    // are not the driven value and an earlier read of them is stale.
    // CHECK-LABEL: simulation.func @resolved(
    // CHECK: simulation.net.read
    // CHECK: simulation.driver.drive
    // CHECK: simulation.net.read
    simulation.func @resolved(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %v: !l8 {simulation.capture_kind = 2 : i32})
        -> (!l8, !l8) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %n1 = simulation.context.net %ctx[1] : !n8
      %before = simulation.net.read %n1 : !n8 -> !l8
      %d2 = simulation.context.driver %ctx[2] : !d8
      simulation.driver.drive %d2 = %v : !d8, !l8
      %after = simulation.net.read %n1 : !n8 -> !l8
      simulation.return %before, %after : !l8, !l8
    }

    // A variable load after a store takes the stored value; a call may write
    // any state, so the load after it stays.
    // CHECK-LABEL: simulation.func @variable(
    // CHECK-SAME: %[[X:[a-z0-9]+]]: i8
    // CHECK: simulation.ref.store %[[X]]
    // CHECK-NOT: simulation.ref.load
    // CHECK: simulation.call @callee
    // CHECK: %[[RELOAD:.*]] = simulation.ref.load
    // CHECK: simulation.return %[[X]], %[[RELOAD]]
    simulation.func @variable(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %x: i8 {simulation.capture_kind = 2 : i32})
        -> (i8, i8) attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[0] : !r8
      simulation.ref.store %x to %r : i8, !r8
      %first = simulation.ref.load %r : !r8 -> i8
      simulation.call @callee(%ctx) : (!c) -> ()
      %second = simulation.ref.load %r : !r8 -> i8
      simulation.return %first, %second : i8, i8
    }
    simulation.func @callee(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      simulation.return
    }

    // A context import may call exported subroutines that write any state
    // (35.5.3); other imports reach state only through their arguments.
    // CHECK-LABEL: simulation.func @dpi(
    // CHECK-SAME: %[[Y:[a-z0-9]+]]: i8
    // CHECK: simulation.dpi.call "plain"
    // CHECK-NOT: simulation.ref.load
    // CHECK: simulation.dpi.call "context"
    // CHECK: %[[AFTER:.*]] = simulation.ref.load
    // CHECK: simulation.return %[[Y]], %[[AFTER]]
    simulation.func @dpi(%ctx: !c {simulation.capture_kind = 0 : i32},
                         %y: i8 {simulation.capture_kind = 2 : i32})
        -> (i8, i8) attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %r = simulation.context.storage %ctx[0] : !r8
      simulation.ref.store %y to %r : i8, !r8
      %s0 = simulation.dpi.call "plain" id 1 scope 0 context %ctx : !c() {
          abi_signature = [], is_context = false, is_pure = false,
          is_task = false, source_column = 1 : i32, source_file = "t.sv",
          source_line = 1 : i32} : () -> !runtime.status
      %first = simulation.ref.load %r : !r8 -> i8
      %s1 = simulation.dpi.call "context" id 2 scope 0 context %ctx : !c() {
          abi_signature = [], is_context = true, is_pure = false,
          is_task = false, source_column = 1 : i32, source_file = "t.sv",
          source_line = 2 : i32} : () -> !runtime.status
      %second = simulation.ref.load %r : !r8 -> i8
      simulation.return %first, %second : i8, i8
    }

    // Connected nets are one simulated net (23.3.3.7): a drive of one member
    // changes the others, so no member's bits are known.
    // CHECK-LABEL: simulation.func @connected(
    // CHECK: simulation.net.read
    // CHECK: simulation.driver.drive
    // CHECK: simulation.net.read
    // CHECK: simulation.net.read
    simulation.func @connected(%ctx: !c {simulation.capture_kind = 0 : i32},
                               %v: !l4 {simulation.capture_kind = 2 : i32})
        -> (!l4, !l4, !l4) attributes {entry_kind = 8 : i32, code_unit_id = 8 : i64} {
      %n4 = simulation.context.net %ctx[4] : !n4
      %before = simulation.net.read %n4 : !n4 -> !l4
      %d5 = simulation.context.driver %ctx[5] : !d4
      simulation.driver.drive %d5 = %v : !d4, !l4
      %after = simulation.net.read %n4 : !n4 -> !l4
      %n3 = simulation.context.net %ctx[3] : !n4
      %own = simulation.net.read %n3 : !n4 -> !l4
      simulation.return %before, %after, %own : !l4, !l4, !l4
    }

    // A join keeps a value both paths agree on and drops one they do not.
    // CHECK-LABEL: simulation.func @join(
    // CHECK-SAME: %[[JX:[a-z0-9]+]]: i8
    // CHECK: ^bb3:
    // CHECK-NEXT: %[[JQ:.*]] = simulation.ref.load
    // CHECK-NEXT: simulation.return %[[JX]], %[[JQ]]
    simulation.func @join(%ctx: !c {simulation.capture_kind = 0 : i32},
                          %x: i8 {simulation.capture_kind = 2 : i32},
                          %y: i8 {simulation.capture_kind = 2 : i32},
                          %c: i1 {simulation.capture_kind = 2 : i32})
        -> (i8, i8) attributes {entry_kind = 8 : i32, code_unit_id = 9 : i64} {
      %r0 = simulation.context.storage %ctx[0] : !r8
      %r1 = simulation.context.storage %ctx[1] : !r8
      simulation.ref.store %x to %r0 : i8, !r8
      cf.cond_br %c, ^a, ^b
    ^a:
      simulation.ref.store %y to %r1 : i8, !r8
      cf.br ^j
    ^b:
      simulation.ref.store %x to %r1 : i8, !r8
      cf.br ^j
    ^j:
      %p = simulation.ref.load %r0 : !r8 -> i8
      %q = simulation.ref.load %r1 : !r8 -> i8
      simulation.return %p, %q : i8, i8
    }

    // Only the live edge reaches the join, but its value does not dominate
    // the read there, so the read stays.
    // CHECK-LABEL: simulation.func @dead_edge(
    // CHECK: ^bb3:
    // CHECK-NEXT: %[[DL:.*]] = simulation.ref.load
    // CHECK-NEXT: simulation.return %[[DL]]
    simulation.func @dead_edge(%ctx: !c {simulation.capture_kind = 0 : i32},
                               %x: i8 {simulation.capture_kind = 2 : i32})
        -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 10 : i64} {
      %r = simulation.context.storage %ctx[0] : !r8
      %false = arith.constant false
      cf.cond_br %false, ^dead, ^live
    ^dead:
      cf.br ^join
    ^live:
      %y = arith.addi %x, %x : i8
      simulation.ref.store %y to %r : i8, !r8
      cf.br ^join
    ^join:
      %v = simulation.ref.load %r : !r8 -> i8
      simulation.return %v : i8
    }

    // Two-state slices compose with shifts and ors, least significant first.
    // CHECK-LABEL: simulation.func @integer(
    // CHECK-SAME: %[[IL:[a-z0-9]+]]: i8 {{.*}}, %[[IH:[a-z0-9]+]]: i8
    // CHECK-NOT: simulation.ref.load
    // CHECK-DAG: %[[ZL:.*]] = arith.extui %[[IL]] : i8 to i16
    // CHECK-DAG: %[[ZH:.*]] = arith.extui %[[IH]] : i8 to i16
    // CHECK-DAG: %[[EIGHT:.*]] = arith.constant 8 : i16
    // CHECK: %[[SH:.*]] = arith.shli %[[ZH]], %[[EIGHT]]
    // CHECK: %[[ALL:.*]] = arith.ori %[[ZL]], %[[SH]]
    // CHECK-NOT: simulation.ref.load
    // CHECK: simulation.return %[[ALL]]
    simulation.func @integer(%ctx: !c {simulation.capture_kind = 0 : i32},
                             %lo: i8 {simulation.capture_kind = 2 : i32},
                             %hi: i8 {simulation.capture_kind = 2 : i32})
        -> i16 attributes {entry_kind = 8 : i32, code_unit_id = 11 : i64} {
      %r = simulation.context.storage %ctx[2] : !r16
      %rlo = simulation.ref.extract %r from 0 : !r16 -> !r8
      %rhi = simulation.ref.extract %r from 8 : !r16 -> !r8
      simulation.ref.store %lo to %rlo : i8, !r8
      simulation.ref.store %hi to %rhi : i8, !r8
      %all = simulation.ref.load %r : !r16 -> i16
      simulation.return %all : i16
    }

    // A suspension ends the activation: other processes may change the net
    // before the next one, so the read after resuming stays.
    // CHECK-LABEL: simulation.func @process(
    // CHECK: simulation.suspend.change
    // CHECK: ^bb1:
    // CHECK-NEXT: simulation.net.read
    simulation.func @process(%ctx: !c {simulation.capture_kind = 0 : i32},
                             %v: !l4 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %d0 = simulation.context.driver %ctx[0] : !d8
      %d0lo = simulation.driver.extract %d0 from 0 : !d8 -> !d4
      %n0 = simulation.context.net %ctx[0] : !n8
      %n0lo = simulation.net.extract %n0 from 0 : !n8 -> !n4
      %d4 = simulation.context.driver %ctx[4] : !dpa
      %d4hi = simulation.driver.subelement %d4[[1]] : !dpa -> !d4
      simulation.driver.drive %d0lo = %v : !d4, !l4
      simulation.suspend.change %n0 to ^resume : !n8
    ^resume:
      %now = simulation.net.read %n0lo : !n4 -> !l4
      simulation.driver.drive %d4hi = %now : !d4, !l4
      simulation.suspend.change %n0 to ^resume : !n8
    }
  }
}

// -----

// A writable VPI client may put any value between the store and the load
// (38.34).
// CHECK-LABEL: simulation.design @writable
// CHECK: simulation.ref.store
// CHECK-NEXT: simulation.ref.load
!c = !simulation.context
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @writable attributes {
    compute_graph = #schedule.graph<version = 1, vpi = full, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @variable(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %x: i8 {simulation.capture_kind = 2 : i32})
        -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      simulation.ref.store %x to %r : i8, !simulation.ref<i8>
      %y = simulation.ref.load %r : !simulation.ref<i8> -> i8
      simulation.return %y : i8
    }
  }
}

// -----

// 10.6.1, 10.6.2: an assigned or forced net or variable ignores its writes
// until it is deassigned or released, so a module with any of them forwards
// nothing.
// CHECK-LABEL: simulation.design @released
// CHECK: simulation.ref.store
// CHECK-NEXT: simulation.ref.load
!c = !simulation.context
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @released attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @variable(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %x: i8 {simulation.capture_kind = 2 : i32})
        -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      simulation.ref.store %x to %r : i8, !simulation.ref<i8>
      %y = simulation.ref.load %r : !simulation.ref<i8> -> i8
      simulation.release_override %r assign true : !simulation.ref<i8>
      simulation.return %y : i8
    }
  }
}

// -----

// 28.8, 4.9.5: in a design with pass switches a drive resolves the switch
// channel at once, changing nets other than the driven one.
// CHECK-LABEL: simulation.design @switched
// CHECK: simulation.net.read
// CHECK: simulation.driver.drive
// CHECK: simulation.net.read
!c = !simulation.context
!l1 = !simulation.logic<1>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @switched attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l1 design
    simulation.net.decl 1 in 0 : !l1 design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false
    simulation.driver.decl 0 in 0 drives 0 : !l1 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @switched(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %v: !l1 {simulation.capture_kind = 2 : i32})
        -> (!l1, !l1) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %n1 = simulation.context.net %ctx[1] : !simulation.net<!l1>
      %b = simulation.net.read %n1 : !simulation.net<!l1> -> !l1
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<!l1>
      simulation.driver.drive %d0 = %v : !simulation.driver<!l1>, !l1
      %a = simulation.net.read %n1 : !simulation.net<!l1> -> !l1
      simulation.return %b, %a : !l1, !l1
    }
  }
}

// -----

// Nothing is forwarded below optimization level 1.
// CHECK-LABEL: simulation.design @unoptimized
// CHECK: simulation.ref.store
// CHECK-NEXT: simulation.ref.load
!c = !simulation.context
module attributes {native.optimization_level = 0 : i32} {
  simulation.design @unoptimized attributes {
    compute_graph = #schedule.graph<version = 1, vpi = off, workers = 1,
      nodes = [], edges = [], regions = [
        #schedule.region<kind = active, groups = []>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>]>} {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.func @variable(%ctx: !c {simulation.capture_kind = 0 : i32},
                              %x: i8 {simulation.capture_kind = 2 : i32})
        -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      simulation.ref.store %x to %r : i8, !simulation.ref<i8>
      %y = simulation.ref.load %r : !simulation.ref<i8> -> i8
      simulation.return %y : i8
    }
  }
}
