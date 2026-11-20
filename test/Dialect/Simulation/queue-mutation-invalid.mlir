// RUN: talos-opt %s -split-input-file -verify-diagnostics

func.func @bounded_allocation(%size: i64) {
  // expected-error @+1 {{queue bound must match the result type}}
  %queue = simulation.container.create %size {
    type_id = 1 : i64, element_kind = #simulation.element_kind<bits>,
    element_flags = #simulation.element_flags<none>, value_size = 1 : i64,
    alignment = 1 : i64, bit_width = 8 : i64, trace_offsets = array<i64>,
    trace_kinds = array<i32>, container_kind = #simulation.container_kind<queue>,
    bound = 2 : i64} : (i64) -> !simulation.queue<i8, 0>
  return
}

// -----

func.func @bounded_append(%q: !simulation.queue<i8, 2>, %v: i8) {
  // expected-error @+1 {{requires an unbounded queue}}
  simulation.queue.push_back %v into %q : !simulation.queue<i8, 2>, i8
  return
}

// -----

func.func @wrong_element(%q: !simulation.queue<i8, 0>, %v: i32) {
  // expected-error @+1 {{value type must match the queue element}}
  simulation.queue.push_back %v into %q : !simulation.queue<i8, 0>, i32
  return
}

// -----

func.func @wrong_result(%q: !simulation.queue<i8, 0>, %index: i64) {
  // expected-error @+1 {{result type must match the queue element}}
  %value = simulation.queue.pop %q[%index] : !simulation.queue<i8, 0> -> i32
  return
}
