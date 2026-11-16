// RUN: talos-opt %s --split-input-file --verify-diagnostics --allow-unregistered-dialect --test-talos-encode-random-programs

module {
  func.func @truncated(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires a complete version-2 program header}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "ODR1"} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @version(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires a version-2 random program}}
    %r:5 = "test.random.function_stage"(%ctx, %start, %start, %state, %state, %state, %state) {program = [
      "version 1 width 1 captures 0 flags [EXACT_UNIFORM, HAS_FUNCTION_PRIORITY]",
      "PUSH_VARIABLE width 1",
      "END_HARD width 1"]} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @flags(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires exact uniform function-priority sampling}}
    %r:5 = "test.random.function_stage"(%ctx, %start, %start, %state, %state, %state, %state) {program = [
      "version 2 width 1 captures 0 flags [EXACT_UNIFORM]"]} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @width(%ctx: !simulation.context, %start: i64, %state: i64) {
    // expected-error @+1 {{program width must fit the assignment's word inventory}}
    %r:5 = "test.random.function_stage"(%ctx, %start, %start, %state, %state, %state, %state) {program = [
      "version 2 width 65 captures 0 flags [EXACT_UNIFORM, HAS_FUNCTION_PRIORITY]"]} : (!simulation.context, i64, i64, i64, i64, i64, i64) -> (i64, i1, i64, i64, i1)
    return
  }
}

// -----

module {
  func.func @captures(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{program capture count must match the capture operands}}
    %r:5 = "test.random.function_stage"(%ctx, %start, %start, %state, %state, %state, %state) {program = [
      "version 2 width 1 captures 1 flags [EXACT_UNIFORM, HAS_FUNCTION_PRIORITY]"]} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}
