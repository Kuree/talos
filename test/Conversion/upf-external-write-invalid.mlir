// RUN: talos-opt %s --split-input-file --elaborate-upf --verify-diagnostics --verify-each -o /dev/null
// Guarded driver NBAs must not silently bypass source epochs.
module {
  upf.supply @p names ["/top/P"] writable = true
  upf.domain @PD elements ["top.dut"] power @p on []
  simulation.design @driver {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 0 : i1 design hierarchy "top.clk"
    simulation.net.decl 0 in 0 : !simulation.logic<8> design hierarchy "top.outside"
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<8> design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<8>>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %value = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      // expected-error @+1 {{guarded UPF NBA requires a storage reference; driver NBA cancellation is not implemented}}
      simulation.nba.enqueue %value to %driver : (!simulation.logic<8>, !simulation.driver<!simulation.logic<8>>) -> ()
      cf.br ^wait
    }
  }
}

// -----

// A switched source writing only AON roots still needs its statement guard;
// persistent copies are staged even when the destination itself has no PD.
module {
  upf.supply @p names ["/top/P"] writable = true
  upf.domain @PD elements ["top.dut"] power @p on []
  simulation.design @copy {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 0 : i8 design hierarchy "top.from"
    simulation.storage.decl 1 in 0 : i8 design hierarchy "top.to"
    simulation.storage.decl 2 in 0 : i1 design hierarchy "top.clk"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 1 always hierarchy "top.dut.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %clk = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %from = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %to = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      // expected-error @+1 {{UPF ordinary state through copied or indirect argument references is not implemented}}
      simulation.ref.copy %from to %to : !simulation.ref<i8>
      cf.br ^wait
    }
  }
}

// -----

// A forged repeating marker cannot turn a Change event into a sequential
// actor: external level restoration still requires its own producer model.
module {
  upf.supply @p names ["/top/P"] writable = true
  upf.domain @PD elements ["top.dut"] power @p on []
  simulation.design @change {
    simulation.scope.decl 0 hierarchy "top"
    simulation.scope.decl 1 parent 0 hierarchy "top.dut" source_definition "leaf"
    simulation.storage.decl 0 in 0 : i1 design hierarchy "top.clk"
    simulation.storage.decl 1 in 1 : i1 design hierarchy "top.dut.q"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "top.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %q = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge change %clk to ^body {schedule.repeating_always_wait} : !simulation.ref<i1>
    ^body:
      %value = arith.constant true
      // expected-error @+1 {{UPF external writes require Initial or a repeating edge actor}}
      simulation.ref.store %value to %q : i1, !simulation.ref<i1>
      cf.br ^wait
    }
  }
}
