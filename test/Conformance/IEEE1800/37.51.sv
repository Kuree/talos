// CLAUSE: Property declaration: a property decl gives its name, formals in order with direction, type and default, and a property inst gives its arguments with defaults filled in
// XFAIL: *
// property declarations report spec=null and property instances are null
// RUN: %clang -c -fPIC %S/Inputs/37.51/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: decl type=vpiPropertyDecl name=p
// CHECK: full=top.p
// CHECK-NEXT: formal x nodir=1 input=0 typed=0 default=null
// CHECK-NEXT: formal y nodir=1 input=0 typed=1 default=3
// CHECK-NEXT: formal z nodir=0 input=1 typed=1 default=5
// CHECK-NEXT: spec=vpiPropertySpec
// CHECK: inst type=vpiPropertyInst
// CHECK-NEXT: decl=p
// CHECK-NEXT: arg a
// CHECK-NEXT: arg 3
// CHECK-NEXT: arg 5

// Detail 2: pa's instance omits y and z, so their default values appear as its arguments. Detail 5: only z is a local variable argument.
module top;
  logic clk = 0, a = 1;
  property p(x, int y = 3, local input int z = 5);
    @(posedge clk) x |-> y + z > 0;
  endproperty
  pa: assert property (p(a));
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
