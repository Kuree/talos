// RUN: talos-opt %s --split-input-file --elaborate-upf --canonicalize --cse --verify-each | FileCheck %s --implicit-check-not=.epoch --implicit-check-not=.previous --implicit-check-not=.normal --implicit-check-not=simulation.power.
// IEEE 1801-2018 6.20/9.2.2: no default monitor or corruption machinery
// for an empty direct extent; an empty switched extent retains only its
// physical input/control-to-output monitor and no guard/epoch ABI.
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.domain @Empty elements [] power @rail on []
  // CHECK-LABEL: simulation.design @empty_direct
  simulation.design @empty_direct {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    // CHECK: simulation.func @root
    // CHECK-NOT: simulation.spawn
    // CHECK: simulation.return
    // CHECK-NOT: simulation.func
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}

// -----

#on = #upf.expression<[#upf.token<opcode = control, control = "top.en">]>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @out names ["/top/OUT"] writable = false
  upf.domain @Empty elements [] power @out on [#upf.state<name = "ON", condition = #on>] {input = @rail}
  // CHECK-LABEL: simulation.design @empty_switched
  simulation.design @empty_switched {
    simulation.scope.decl 0 hierarchy "top"
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design hierarchy "top.en"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    // CHECK: simulation.spawn @__upf_Empty.switch
    // CHECK: simulation.func {{.*}}@__upf_Empty.switch
    // CHECK: simulation.ref.store
    // CHECK: simulation.suspend.any
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
      %one = simulation.logic.constant 1 : i1, 0 : i1 : !simulation.logic<1>
      simulation.ref.store %one to %ref : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.return
    }
  }
}
