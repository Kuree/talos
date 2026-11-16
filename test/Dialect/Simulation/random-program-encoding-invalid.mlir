// RUN: talos-opt %s --split-input-file --verify-diagnostics --allow-unregistered-dialect --test-talos-encode-random-programs

func.func @no_header(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{random program must start with a version line}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "PUSH_VARIABLE width 1"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @opcode(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{unknown random program opcode 'PUSH_BOGUS'}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 0 flags []",
    "PUSH_BOGUS width 1"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @flag(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{unknown random program flag 'HAS_BOGUS'}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 0 flags [HAS_SOFT, HAS_BOGUS]"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @count(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{random program header states instructions 2 but has 1}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 instructions 2 captures 0 flags []",
    "PUSH_VARIABLE width 1"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @literal(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{random program field 'value' does not fit 4 bits}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 2 width 8 captures 0 flags []",
    "PUSH_LITERAL width 4 value 16"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @edge(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{solve edges require HAS_SOLVE_BEFORE}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 0 flags []",
    "edge before 0x1 after 0x2 block 0 flags 0"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @sections(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{the test encoder writes no dist, domain or sampler plan sections}}
  %r:3 = "test.random.solve_wide"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 0 flags [HAS_DIST]"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}

// -----

func.func @name(%ctx: !simulation.context, %v: i8, %s: i64) {
  // expected-error @+1 {{'simulation.random.bogus' is not a registered operation}}
  %r:3 = "test.random.bogus"(%ctx, %v, %v, %s, %s, %s, %s) {program = [
    "version 1 width 8 captures 0 flags []"]} : (!simulation.context, i8, i8, i64, i64, i64, i64) -> (i8, i1, i64)
  return
}
