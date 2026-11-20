// RUN: talos-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{fixed DPI open-array extents disagree with the transport}}
#bad_extent = #dpi.open_array_abi<storage = 0, elementKind = bit,
    elementWidth = 1, transportWidth = 8, transportFourState = false,
    fourState = false, elementCSize = 1, elementCAlignment = 1,
    elementStringCount = 0, elementLeaves = [0, 0, 0, 0, 1, 0, 0, 0],
    packedLeft = 0, packedRight = 0, ranges = [7, 0],
    sourceRanges = [0, 6], shapePlan = []>
module {}

// -----

// expected-error @+1 {{recursive DPI shape bounds disagree with the descriptor}}
#bad_shape = #dpi.open_array_abi<storage = 2, elementKind = int,
    elementWidth = 32, transportWidth = 64, transportFourState = false,
    fourState = false, elementCSize = 4, elementCAlignment = 4,
    elementStringCount = 0, elementLeaves = [0, 0, 0, 4, 32, 0, 1, 0],
    packedLeft = 31, packedRight = 0, ranges = [0, 1], sourceRanges = [4, 3],
    shapePlan = [1, 0, 2, 0, 0, 32, 0, 2]>
module {}

// -----

#a = #dpi.open_array_abi<storage = 0, elementKind = bit,
    elementWidth = 1, transportWidth = 8, transportFourState = false,
    fourState = false, elementCSize = 1, elementCAlignment = 1,
    elementStringCount = 0, elementLeaves = [0, 0, 0, 0, 1, 0, 0, 0],
    packedLeft = 0, packedRight = 0, ranges = [7, 0], sourceRanges = [7, 0], shapePlan = []>
#b = #dpi.open_array_abi<storage = 0, elementKind = bit,
    elementWidth = 1, transportWidth = 8, transportFourState = false,
    fourState = false, elementCSize = 1, elementCAlignment = 1,
    elementStringCount = 0, elementLeaves = [0, 0, 0, 0, 1, 0, 0, 0],
    packedLeft = 0, packedRight = 0, ranges = [1, 8], sourceRanges = [1, 8], shapePlan = []>
simulation.design @mismatch {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 initial hierarchy "host"
  simulation.func private @host(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
      attributes {code_unit_id = 1 : i64, entry_kind = 1 : i32} {
    %arg = arith.constant 0 : i8
    // expected-error @+1 {{DPI formal copy-out must use its input layout}}
    %ret:2 = simulation.dpi.call "edit" id 1 scope 0 context %ctx : !simulation.context(%arg) {
      abi_signature = [#dpi.abi<kind = open_array, direction = inout, width = 1, fourState = false, isSigned = false>,
                       #dpi.abi<kind = open_array, direction = output, width = 1, fourState = false, isSigned = false>],
      open_array_layouts = [#a, #b], is_context = false, is_pure = false, is_task = false,
      source_column = 1 : i32, source_file = "host.sv", source_line = 1 : i32
    } : (i8) -> (i8, !runtime.status)
    simulation.return
  }
}
