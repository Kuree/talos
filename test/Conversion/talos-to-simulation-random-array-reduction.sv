// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos --talos-sim-prepare | FileCheck %s

// IEEE 1800-2023 18.5.7.2: in a constraint, an array reduction method is an
// expression iterated over each element, joined by the method's operator, in
// the type of the element or of the with expression.
class Fixed;
  rand bit [3:0] a[2:1];
  constraint c { a.sum() == 5; }
endclass
class With;
  rand int a[2];
  constraint c { a.product() with (item + item.index) == 6; }
endclass
class Dynamic;
  rand bit [7:0] d[];
  constraint c { d.size() <= 2; d.and() == 8'h0f; }
endclass
class State;
  int s[];
  rand int x;
  constraint c { x == s.sum(); }
endclass
module top;
  Fixed f = new;
  With w = new;
  Dynamic d = new;
  State s = new;
  initial begin
    void'(f.randomize());
    void'(w.randomize());
    void'(d.randomize());
    void'(s.randomize());
  end
endmodule

// In declared order, in the element's own width, so that the sum can wrap.
// CHECK-LABEL: referenced_path = "top.f"
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 0 : i32{{.*}}semantic_type = !talos.ranged_packed_array<3 : 0
// CHECK: talos.sv.expression.element_select
// CHECK: referenced_path = "Fixed::a"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "2"
// CHECK: talos.sv.expression.element_select
// CHECK: referenced_path = "Fixed::a"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "1"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "5"

// item is the element and item.index its index.
// CHECK-LABEL: referenced_path = "top.w"
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 2 : i32
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 0 : i32
// CHECK: referenced_path = "With::a"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "0"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "0"
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 0 : i32
// CHECK: referenced_path = "With::a"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "1"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "1"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "6"

// An element at or beyond size() contributes the operator's identity, not a
// requirement that the element exists.
// CHECK-LABEL: referenced_path = "top.d"
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 5 : i32
// CHECK: talos.sv.expression.conditional_op attributes {condition_count = 1
// CHECK: talos.sv.expression.binary_op attributes {{{.*}}operator_kind = 16 : i32
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "0"
// CHECK: callee_name = "size"
// CHECK: talos.sv.expression.element_select
// CHECK: referenced_path = "Dynamic::d"
// CHECK: talos.sv.expression.integer_literal attributes {constant_value = "255"

// A container the call does not randomize stays a captured value.
// CHECK-LABEL: referenced_path = "top.s"
// CHECK: referenced_path = "State::x"
// CHECK: callee_name = "sum"
// CHECK: referenced_path = "State::s"
