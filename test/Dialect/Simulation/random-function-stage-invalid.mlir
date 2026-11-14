// RUN: talos-opt %s --split-input-file --verify-diagnostics

module {
  func.func @truncated(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires a complete version-2 program header}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "\4F\44\52\31"} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @version(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires a version-2 random program}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "\4F\44\52\31\01\00\20\00\01\00\00\00\00\00\00\00\00\00\00\00\60\00\00\00\00\00\00\00\00\00\00\00"} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @flags(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{requires exact uniform function-priority sampling}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "\4F\44\52\31\02\00\20\00\01\00\00\00\00\00\00\00\00\00\00\00\20\00\00\00\00\00\00\00\00\00\00\00"} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}

// -----

module {
  func.func @width(%ctx: !simulation.context, %start: i64, %state: i64) {
    // expected-error @+1 {{program width must fit the assignment's word inventory}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "\4F\44\52\31\02\00\20\00\41\00\00\00\00\00\00\00\00\00\00\00\60\00\00\00\00\00\00\00\00\00\00\00"} : (!simulation.context, i64, i64, i64, i64, i64, i64) -> (i64, i1, i64, i64, i1)
    return
  }
}

// -----

module {
  func.func @captures(%ctx: !simulation.context, %start: i1, %state: i64) {
    // expected-error @+1 {{program capture count must match the capture operands}}
    %r:5 = simulation.random.function_stage %ctx, %start, %start, %state, %state, %state, %state {program = "\4F\44\52\31\02\00\20\00\01\00\00\00\00\00\00\00\01\00\00\00\60\00\00\00\00\00\00\00\00\00\00\00"} : (!simulation.context, i1, i1, i64, i64, i64, i64) -> (i1, i1, i64, i1, i1)
    return
  }
}
