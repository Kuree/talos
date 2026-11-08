#u1 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [0, 0], children = [], childNames = []>
#s1 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [0, 0], children = [], childNames = []>
#u3 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [2, 0], children = [], childNames = []>
#s3 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [2, 0], children = [], childNames = []>
#u8 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [7, 0], children = [], childNames = []>
#s8 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [7, 0], children = [], childNames = []>
#u16 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [15, 0], children = [], childNames = []>
#s16 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [15, 0], children = [], childNames = []>
#u32 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [31, 0], children = [], childNames = []>
#s32 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [31, 0], children = [], childNames = []>
#u63 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [62, 0], children = [], childNames = []>
#s63 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [62, 0], children = [], childNames = []>
#u64 = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [63, 0], children = [], childNames = []>
#s64 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [63, 0], children = [], childNames = []>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @packed_callback_values {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.scope.decl 1 parent 0 hierarchy "top" vpi_kind 32
    simulation.storage.decl 0 in 1 : !simulation.logic<1> design hierarchy "top.u1" {vpi_type = #u1}
    simulation.storage.decl 1 in 1 : !simulation.logic<1> design hierarchy "top.s1" {vpi_type = #s1}
    simulation.storage.decl 2 in 1 : !simulation.logic<3> design hierarchy "top.u3" {vpi_type = #u3}
    simulation.storage.decl 3 in 1 : !simulation.logic<3> design hierarchy "top.s3" {vpi_type = #s3}
    simulation.storage.decl 4 in 1 : !simulation.logic<8> design hierarchy "top.u8" {vpi_type = #u8}
    simulation.storage.decl 5 in 1 : !simulation.logic<8> design hierarchy "top.s8" {vpi_type = #s8}
    simulation.storage.decl 6 in 1 : !simulation.logic<16> design hierarchy "top.u16" {vpi_type = #u16}
    simulation.storage.decl 7 in 1 : !simulation.logic<16> design hierarchy "top.s16" {vpi_type = #s16}
    simulation.storage.decl 8 in 1 : !simulation.logic<32> design hierarchy "top.u32" {vpi_type = #u32}
    simulation.storage.decl 9 in 1 : !simulation.logic<32> design hierarchy "top.s32" {vpi_type = #s32}
    simulation.storage.decl 10 in 1 : !simulation.logic<63> design hierarchy "top.u63" {vpi_type = #u63}
    simulation.storage.decl 11 in 1 : !simulation.logic<63> design hierarchy "top.s63" {vpi_type = #s63}
    simulation.storage.decl 12 in 1 : !simulation.logic<64> design hierarchy "top.u64" {vpi_type = #u64}
    simulation.storage.decl 13 in 1 : !simulation.logic<64> design hierarchy "top.s64" {vpi_type = #s64}
    simulation.code_unit.decl 1 in 1 root_initializer hierarchy "top.root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}
