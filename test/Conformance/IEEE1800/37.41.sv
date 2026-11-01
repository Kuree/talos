// CLAUSE: Task and function declaration: types, lifetime, size, return variable, io decls, method visibility and full name, and DPI properties
// XFAIL: *
// function flags vpiSized, vpiInt and vpiReal are wrong, and a logic return reports vpiReg
// RUN: %clang -c -fPIC %S/Inputs/37.41/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %clang -c -fPIC %S/Inputs/37.41/twice.c -o %t.helper1.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o %t.helper1.o -o %t.exe
// RUN: %t.exe
// CHECK: f8 type=vpiFunction full=top.f8 automatic=1 size=8 signed=0 method=0 public=1 sized=1
// CHECK-NEXT: return type=vpiLogicVar name=f8 size=8
// CHECK-NEXT: io x input=1
// CHECK-NEXT: io y input=1
// CHECK: fi type=vpiFunction full=top.fi automatic=0 size=32 signed=1 method=0 public=1 int=1
// CHECK-NEXT: return type=vpiIntVar name=fi size=32
// CHECK: fr type=vpiFunction full=top.fr automatic=0 real=1
// CHECK: fv type=vpiFunction size=0
// CHECK: tk type=vpiTask full=top.tk automatic=1
// CHECK-NEXT: io a input=1
// CHECK-NEXT: io b input=0 output=1
// CHECK: ts type=vpiTask full=top.ts automatic=0
// CHECK: method full=top.C::lm is_method=1 local=1 protected=0 public=0
// CHECK: method full=top.C::pm is_method=1 local=0 protected=1 public=0
// CHECK: method full=top.C::um is_method=1 local=0 protected=0 public=1
// CHECK: probe import=1 export=0 context=1 pure=0 dpic=1 identifier=probe
// CHECK: twice import=1 export=0 context=0 pure=1 dpic=1 identifier=c_twice
// CHECK: fi import=0 export=1
// CHECK: twice(4)=8

module top;
  function automatic logic [7:0] f8(input logic [7:0] x, input int y);
    return x;
  endfunction
  function int fi();
    return 1;
  endfunction
  function void fv();
  endfunction
  function real fr();
    return 1.5;
  endfunction
  task automatic tk(input int a, output int b);
    b = a;
  endtask
  task static ts();
  endtask
  class C;
    local function int lm();
      return 1;
    endfunction
    protected function int pm();
      return 2;
    endfunction
    function int um();
      return 3;
    endfunction
  endclass
  C obj = new;
  import "DPI-C" context function void probe();
  import "DPI-C" pure c_twice = function int twice(int x);
  export "DPI-C" function fi;
  initial begin
    probe();
    $display("twice(4)=%0d", twice(4));
    $finish;
  end
endmodule
