// RUN: talos-opt %s --prepare-upf-snapshot-publications --elaborate-upf --prepare-upf-snapshot-publications --verify-each -o %t
// RUN: FileCheck %s --input-file=%t
// RUN: talos-opt %t --canonicalize --cse --verify-each --canonicalize --cse --verify-each -o /dev/null
// Caller context and reference windows are ordinary SSA formals, including
// forwarding-only helpers. Source identities survive; the owned writer shares
// its existing clock channel and external actors get independent channels.
// CHECK-DAG: "__upf_write.initial_epoch"
// CHECK-DAG: "__upf_target.PD.clock.101.epoch"
// CHECK-DAG: "__upf_target.PD.clock.102.epoch"
// CHECK-DAG: "__upf_clock.55.epoch"
// CHECK-LABEL: simulation.func private @issue(
// CHECK-SAME: i32 {simulation.capture_kind = 1 : i32}
// CHECK-SAME: i1 {simulation.capture_kind = 1 : i32}
// CHECK-SAME: i64 {simulation.capture_kind = 1 : i32}
// CHECK: cf.cond_br
// CHECK: simulation.power.nba.enqueue_view
// CHECK: simulation.observer.bind @__upf_write.allowed.1.1
// CHECK-LABEL: simulation.func private @forward(
// CHECK: simulation.call @issue
// CHECK-SAME: i32, i1, i64, i1, i64
// CHECK-LABEL: simulation.func private @writer_a
// CHECK: simulation.call @forward
// CHECK-LABEL: simulation.func private @writer_b
// CHECK: simulation.call @forward
// CHECK-LABEL: simulation.func private @writer_owned
// CHECK-SAME: code_unit_id = 55 : i64
// CHECK: simulation.call @forward
// CHECK-LABEL: simulation.func private @__upf_clock.55.capture
// CHECK-SAME: -> i67
// CHECK-LABEL: simulation.func private @__upf_write.allowed.0.0
// CHECK-SAME: (%arg0: !simulation.context
// CHECK-NOT: simulation.context.storage
// CHECK: simulation.return

!c = !simulation.context
!r = !simulation.ref<i65>
!b = !simulation.ref<i8>
!n = !simulation.ref<i4>
!clk = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  upf.supply @p names ["/top/P"] writable = true {initial_value = 1 : i64}
  upf.domain @PD elements ["top.dut"] power @p on []
  simulation.design @external_windows {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 1 : i65 design hierarchy "top.dut.q"
    simulation.storage.decl 1 in 0 : i65 design hierarchy "top.outside"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.clk"
    simulation.code_unit.decl 2 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 55 in 1 always hierarchy "top.dut.writer"
    simulation.code_unit.decl 101 in 0 always hierarchy "top.writer_a"
    simulation.code_unit.decl 102 in 0 always hierarchy "top.writer_b"
    simulation.code_unit.decl 103 in 0 function hierarchy "top.issue"
    simulation.code_unit.decl 104 in 0 function hierarchy "top.forward"
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 2 : i64} {
      %q = simulation.context.storage %ctx[0] : !r
      %outside = simulation.context.storage %ctx[1] : !r
      %clk = simulation.context.storage %ctx[2] : !clk
      %zero = arith.constant 0 : i65
      %false = arith.constant false
      %true = arith.constant true
      simulation.ref.store %zero to %q : i65, !r
      simulation.ref.store %zero to %outside : i65, !r
      simulation.ref.store %false to %clk : i1, !clk
      %qi = simulation.ref.extract %q from 4 : !r -> !b
      %oi = simulation.ref.extract %outside from 4 : !r -> !b
      simulation.call @forward(%ctx, %qi, %oi) : (!c, !b, !b) -> ()
      %qa = simulation.ref.extract %q from 20 : !r -> !b
      %oa = simulation.ref.extract %outside from 20 : !r -> !b
      %qb = simulation.ref.extract %q from 40 : !r -> !b
      %ob = simulation.ref.extract %outside from 40 : !r -> !b
      %qc = simulation.ref.extract %q from 56 : !r -> !b
      %oc = simulation.ref.extract %outside from 56 : !r -> !b
      %a = simulation.spawn @writer_a(%ctx, %qa, %oa) : !c, !b, !b -> !simulation.process
      %b = simulation.spawn @writer_b(%ctx, %qb, %ob) : !c, !b, !b -> !simulation.process
      %c = simulation.spawn @writer_owned(%ctx, %qc, %oc) : !c, !b, !b -> !simulation.process
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^clock
    ^clock:
      simulation.ref.store %true to %clk : i1, !clk
      simulation.suspend.delay %delay to ^check
    ^check:
      %v = simulation.ref.load %q : !r -> i65
      %w = simulation.ref.load %outside : !r -> i65
      %expected = arith.constant 14051445242367839280 : i65
      %qok = arith.cmpi eq, %v, %expected : i65
      %ook = arith.cmpi eq, %w, %expected : i65
      %out = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "external windows %0d %0d"
      simulation.display %ctx to %out(%fmt, %qok, %ook) newline = true radix = <decimal> flags = [0,0,0] : !simulation.bytes, i1, i1
      %success = arith.constant 0 : i32
      simulation.finish %ctx, %success
      simulation.return
    }
    simulation.func private @issue(%ctx: !c {simulation.capture_kind = 0 : i32}, %q: !b {simulation.capture_kind = 1 : i32}, %outside: !b {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 103 : i64} {
      %six = arith.constant 6 : i64
      %minus_two = arith.constant -2 : i64
      %a = simulation.ref.dyn_extract %q from %six : (!b, i64) -> !n
      %b = simulation.ref.dyn_extract %q from %minus_two : (!b, i64) -> !n
      %c = simulation.ref.dyn_extract %outside from %six : (!b, i64) -> !n
      %d = simulation.ref.dyn_extract %outside from %minus_two : (!b, i64) -> !n
      %eleven = arith.constant 11 : i4
      %thirteen = arith.constant 13 : i4
      simulation.nba.enqueue %eleven to %a : (i4, !n) -> ()
      simulation.nba.enqueue %thirteen to %b : (i4, !n) -> ()
      simulation.nba.enqueue %eleven to %c : (i4, !n) -> ()
      simulation.nba.enqueue %thirteen to %d : (i4, !n) -> ()
      simulation.return
    }
    simulation.func private @forward(%ctx: !c {simulation.capture_kind = 0 : i32}, %q: !b {simulation.capture_kind = 1 : i32}, %outside: !b {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 104 : i64} {
      simulation.call @issue(%ctx, %q, %outside) : (!c, !b, !b) -> ()
      simulation.return
    }
    simulation.func private @writer_a(%ctx: !c {simulation.capture_kind = 0 : i32}, %q: !b {simulation.capture_kind = 1 : i32}, %outside: !b {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 101 : i64} {
      %clk = simulation.context.storage %ctx[2] : !clk
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !clk
    ^body:
      simulation.call @forward(%ctx, %q, %outside) : (!c, !b, !b) -> ()
      cf.br ^wait
    }
    simulation.func private @writer_b(%ctx: !c {simulation.capture_kind = 0 : i32}, %q: !b {simulation.capture_kind = 1 : i32}, %outside: !b {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 102 : i64} {
      %clk = simulation.context.storage %ctx[2] : !clk
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !clk
    ^body:
      simulation.call @forward(%ctx, %q, %outside) : (!c, !b, !b) -> ()
      cf.br ^wait
    }
    simulation.func private @writer_owned(%ctx: !c {simulation.capture_kind = 0 : i32}, %q: !b {simulation.capture_kind = 1 : i32}, %outside: !b {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 55 : i64} {
      %clk = simulation.context.storage %ctx[2] : !clk
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !clk
    ^body:
      simulation.call @forward(%ctx, %q, %outside) : (!c, !b, !b) -> ()
      cf.br ^wait
    }
  }
}
