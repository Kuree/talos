// RUN: env TALOS_TEST_INPUT=%s TALOS_TEST_OUTPUT=%t.dump \
// RUN:   TALOS_TEST_VPI=full %obj_root/test/talos-design-database-dump-test \
// RUN:   --gtest_filter=GeneratedDesignDatabase.Dump
// RUN: FileCheck %s < %t.dump

// IEEE 1800-2023 7.3.2 specifies a tag's size and position only for the packed
// representation of a tagged union. An unpacked tagged union keeps its tag,
// including the inactive state, in physical storage alone (2 bits for 2
// members over 2 x 64 payload bits), while its VPI semantic type carries no
// tag bits. The runtime validator accepts that pairing instead of rejecting
// the design at startup.
!tu = !simulation.unpacked_union<fields = [
    #simulation.field<name = "i", type = i32, ordinal = 0, packedOffset = 0>,
    #simulation.field<name = "r", type = f64, ordinal = 1, packedOffset = 0>],
    isTagged = true>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @unpacked_tagged_union {
    simulation.scope.decl 0 hierarchy "$root"
    simulation.scope.decl 1 parent 0 hierarchy "top" vpi_kind 32
    simulation.vpi_object.anchor @top id 0 type 32 in 1 ordinal 0
        hierarchy "top" debug "top" {
      backing = #simulation.vpi_backing<kind = scope, id = 1 : i64>
    }
    simulation.storage.decl 0 in 1 : !tu design hierarchy "top.ta" debug "ta" {
      observability = 2 : i32,
      vpi_type = #simulation.vpi_type<kind = unpacked_union, isSigned = false,
          isFourState = false, name = "tu_t", range = [],
          children = [
            #simulation.vpi_type<kind = int, isSigned = true,
                isFourState = false, range = [31, 0], children = [],
                childNames = []>,
            #simulation.vpi_type<kind = real, isSigned = false,
                isFourState = false, range = [], children = [],
                childNames = []>],
          childNames = ["i", "r"], isTagged = true, isSoft = false,
          bitWidth = 0 : i64, selectableWidth = 64 : i64,
          bitstreamWidth = 64 : i64, tagBits = 0 : i64,
          childOrdinals = [0, 1], childPackedOffsets = [0, 0],
          childRandTypes = [1, 1]>
    }
    simulation.code_unit.decl 1 in 1 initial hierarchy "top.initial"
    simulation.func @initial(%ctx: !simulation.context
        {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      simulation.return
    }
  }
}

// CHECK: object name=top.ta kind=2 vpi_kind=619 {{.*}} width=130 range=[129:0] {{.*}} type_kind=4 type_flags=0x8
// CHECK: semantic_type index=0 kind=22 flags=0x800 public_vpi_kind=639 {{.*}} name=tu_t {{.*}} bit_width=0 tag_bits=0
