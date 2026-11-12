// RUN: env TALOS_TEST_INPUT=%s %obj_root/test/talos-design-database-dump-test --gtest_filter=GeneratedDesignDatabase.FrozenPackedParameters
// RUN: talos-opt %s --emit-bytecode -o %t.bc
// RUN: env TALOS_TEST_INPUT=%t.bc %obj_root/test/talos-design-database-dump-test --gtest_filter=GeneratedDesignDatabase.FrozenPackedParameters

// LRM 7.4.1: every packed dimension contributes to a single vector's width.
// Enum-typed parameters also use their base width (6.19), even though the
// parameter object itself is not an EnumConst. Preserve signed/four-state
// metadata while validating and reading each complete frozen value.
#u9 = #simulation.vpi_type<kind = bit, isSigned = false, isFourState = false, range = [8, 0], children = [], childNames = []>
#matrix = #simulation.vpi_type<kind = packed_array, isSigned = false, isFourState = false, range = [1, 0], children = [#u9], childNames = []>
#u4 = #simulation.vpi_type<kind = bit, isSigned = false, isFourState = false, range = [3, 0], children = [], childNames = []>
#row = #simulation.vpi_type<kind = packed_array, isSigned = false, isFourState = false, range = [-1, 1], children = [#u4], childNames = []>
#cube = #simulation.vpi_type<kind = packed_array, isSigned = false, isFourState = false, range = [0, 1], children = [#row], childNames = []>
#choice = #simulation.vpi_type<kind = enum, isSigned = false, isFourState = false, name = "choice_t", range = [], children = [#u9], childNames = [], typedefAliases = [@choice_type]>
#logic9 = #simulation.vpi_type<kind = logic, isSigned = true, isFourState = true, range = [8, 0], children = [], childNames = []>
#signed = #simulation.vpi_type<kind = packed_array, isSigned = true, isFourState = true, range = [1, 0], children = [#logic9], childNames = []>
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @frozen_packed {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.vpi_object.anchor @pkg id 0 type 600 in 0 ordinal 0 hierarchy "pkg" debug "pkg"
    simulation.vpi_typespec.decl @choice_type id 0 in 0 owner @pkg hierarchy "pkg::choice_t" debug "choice_t" {target_type = #choice}
    simulation.vpi_object.anchor @matrix id 1 type 41 in 0 parent @pkg ordinal 0 hierarchy "pkg::Packed" debug "Packed" {vpi_type = #matrix, immutable_value = #simulation.frozen_constant<value = [174762 : i18, 0 : i18], isSigned = false> : !simulation.packed_array<1 : 0 x i9>}
    simulation.vpi_object.anchor @cube id 2 type 41 in 0 parent @pkg ordinal 1 hierarchy "pkg::Cube" debug "Cube" {vpi_type = #cube, immutable_value = #simulation.frozen_constant<value = [11259375 : i24, 0 : i24], isSigned = false> : !simulation.packed_array<0 : 1 x !simulation.packed_array<-1 : 1 x i4>>}
    simulation.vpi_object.anchor @choice id 3 type 41 in 0 parent @pkg ordinal 2 hierarchy "pkg::Enum" debug "Enum" {vpi_type = #choice, immutable_value = #simulation.frozen_constant<value = [421 : i9, 0 : i9], isSigned = false> : i9}
    simulation.vpi_object.anchor @signed id 4 type 41 in 0 parent @pkg ordinal 3 hierarchy "pkg::Signed" debug "Signed" {vpi_type = #signed, immutable_value = #simulation.frozen_constant<value = [-3 : i18, 0 : i18], isSigned = true> : !simulation.packed_array<1 : 0 x !simulation.logic<9>>}
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}
