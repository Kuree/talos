#logic8 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [7, 0], children = [], childNames = []>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @observable_bytecode {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.scope.decl 1 parent 0 hierarchy "top" vpi_kind 32
    simulation.storage.decl 0 in 1 : !simulation.logic<8> design hierarchy "top.value" {vpi_type = #logic8}
    simulation.storage.decl 1 in 1 : !simulation.logic<8> design hierarchy "top.later" {vpi_type = #logic8}
    simulation.code_unit.decl 1 in 1 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 11 in 1 initial hierarchy "top.writer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %value = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %later = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<8>>
      %p = simulation.spawn @writer(%ctx, %value, %later) : !simulation.context, !simulation.ref<!simulation.logic<8>>, !simulation.ref<!simulation.logic<8>> -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %value: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %later: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 11 : i64} {
      %zero = simulation.logic.constant 0 : i8, 0 : i8 : !simulation.logic<8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      %two = simulation.logic.constant 2 : i8, 0 : i8 : !simulation.logic<8>
      %three = simulation.logic.constant 3 : i8, 0 : i8 : !simulation.logic<8>
      %four = simulation.logic.constant 4 : i8, 0 : i8 : !simulation.logic<8>
      %nine = simulation.logic.constant 9 : i8, 0 : i8 : !simulation.logic<8>
      simulation.ref.store %zero to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %one to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %two to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %two to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %nine to %later : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.nba.enqueue %three to %value : (!simulation.logic<8>, !simulation.ref<!simulation.logic<8>>) -> ()
      simulation.nba.enqueue %four to %value : (!simulation.logic<8>, !simulation.ref<!simulation.logic<8>>) -> ()
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^resume
    ^resume:
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !simulation.logic<8>
      %z = simulation.logic.constant -1 : i8, -1 : i8 : !simulation.logic<8>
      simulation.ref.store %x to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %z to %value : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
  }
}
