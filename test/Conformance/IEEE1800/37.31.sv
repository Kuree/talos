// CLAUSE: Class definition: a class defn gives its name and virtual flag, static and automatic members, declared methods only, and its derivation links
// XFAIL: *
// vpiVirtual reports -1 (undefined) for classes instead of vpiTrue or vpiFalse
// RUN: %clang -c -fPIC %S/Inputs/37.31/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiClassDefn name=Base virtual=1
// CHECK: type=vpiClassDefn name=Derived virtual=0
// CHECK-DAG: var own_auto
// CHECK-DAG: var own_static
// CHECK-DAG: method new
// CHECK-DAG: method own_task
// CHECK-DAG: method own_sfunc
// CHECK: base method base_m
// CHECK: base methods=1
// CHECK: derived Derived
// CHECK: derived classes=1
// CHECK: extends=Base

// Detail 1: Base has neither an explicit new nor an explicit randomize, so its only method is base_m.
module top;
  virtual class Base;
    rand int base_auto;
    function void base_m(); endfunction
  endclass
  class Derived extends Base;
    int own_auto;
    static int own_static;
    function new(); endfunction
    task own_task(); endtask
    static function void own_sfunc(); endfunction
  endclass
  Derived d;
  import "DPI-C" context function void probe();
  initial begin d = new; probe(); $finish; end
endmodule
