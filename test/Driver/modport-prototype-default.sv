// RUN: %talos -emit-slang %s -o - | FileCheck %s

// IEEE 1800-2023 25.7: when a prototype and the subroutine declaration both
// give an argument a default, a call through the prototype uses the
// prototype's default. A call that does not go through the prototype uses the
// declaration's. Slang binds the declaration's default, so the frontend rebinds
// the call, which still records the argument as defaulted.
interface Bus;
  function int f(input int x = 1);
    return x;
  endfunction
  modport client(import function int f(input int x = 2));
endinterface
module Reader(Bus.client b);
  int value;
  initial value = b.f();
endmodule
module ArrayReader(Bus.client b[2]);
  int value;
  initial value = b[1].f();
endmodule
class Handle;
  virtual Bus.client b;
  function int get();
    return b.f();
  endfunction
endclass
module top;
  Bus bus(), buses[2]();
  Reader r(bus);
  ArrayReader a(buses);
  int value;
  initial value = bus.f();
endmodule

// Through a virtual interface bound to the modport.
// CHECK-LABEL: slang.symbol.subroutine @{{[^ ]+}}.get attributes
// CHECK: callee_name = "f",{{.*}}defaulted_arguments = array<i64: 1>
// CHECK: slang.expression.integer_literal attributes {constant_value = "2"

// Through an interface port.
// CHECK-LABEL: slang.symbol.instance_body @{{[^ ]+}}.Reader attributes
// CHECK: callee_name = "f",{{.*}}defaulted_arguments = array<i64: 1>
// CHECK-NEXT: slang.expression.integer_literal attributes {constant_value = "2"

// Through an element of an interface port array.
// CHECK-LABEL: slang.symbol.instance_body @{{[^ ]+}}.ArrayReader attributes
// CHECK: callee_name = "f",{{.*}}defaulted_arguments = array<i64: 1>
// CHECK-NEXT: slang.expression.integer_literal attributes {constant_value = "2"

// Directly into the interface, without the prototype.
// CHECK: callee_name = "f",{{.*}}defaulted_arguments = array<i64: 1>
// CHECK-NEXT: slang.expression.integer_literal attributes {constant_value = "1"
