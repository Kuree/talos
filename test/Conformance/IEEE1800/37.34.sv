// CLAUSE: Constraint: declaration order, static and extern flags, enabled state after constraint_mode, solve-before ordering and dist items
// XFAIL: *
// constraint vpiEnable reports -1 and constraint items are not iterated
// RUN: %clang -c -fPIC %S/Inputs/37.34/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: constraint first automatic=1 extern=0 enabled=1 parent=vpiClassObj
// CHECK: constraint second automatic=1 extern=1 enabled=0 parent=vpiClassObj
// CHECK: constraint third automatic=0 extern=0 enabled=1 parent=vpiClassObj
// CHECK: first item vpiOperation
// CHECK: first item vpiConstraintOrdering
// CHECK: before=a after=b
// CHECK: third item vpiDistribution
// CHECK: dist expr=b
// CHECK: dist item equal=1 weight=2
// CHECK: dist item divided=1 weight=5

// Details 1, 3 and 4: third is static, second is extern and keeps its prototype's position.
module top;
  class C;
    rand int a, b;
    constraint first { a > 0; solve a before b; }
    extern constraint second;
    static constraint third { b dist { 1 := 2, [3:4] :/ 5 }; }
  endclass
  constraint C::second { b > a; }
  C o;
  import "DPI-C" context function void probe();
  initial begin
    o = new;
    o.second.constraint_mode(0);
    probe();
    $finish;
  end
endmodule
