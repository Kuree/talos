// CLAUSE: Task and function call: a call statement gives its callee and its arguments in order with their values; a method call its prefix; an empty system task argument is a null operation
// XFAIL: *
// call objects report name=null, method call target is missing and vpiUserDefined is -1
// RUN: %clang -c -fPIC %S/Inputs/37.42/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: 9 s
// CHECK: call=vpiFuncCall name=note
// CHECK-NEXT: target=vpiFunction name=note
// CHECK-NEXT: arg {{vpiLogicVar|vpiReg}} value=9
// CHECK-NEXT: arg vpiConstant value=5
// CHECK: call=vpiTaskCall name=tk
// CHECK-NEXT: target=vpiTask name=tk
// CHECK-NEXT: arg vpiOperation value=10
// CHECK: call=vpiMethodFuncCall name=go
// CHECK-NEXT: prefix=obj
// CHECK-NEXT: target=vpiFunction name=go
// CHECK-NEXT: arg vpiConstant value=3
// CHECK: call=vpiSysTaskCall name=$display user=0
// CHECK-NEXT: arg {{vpiLogicVar|vpiReg}} value=9
// CHECK-NEXT: arg null operation
// CHECK-NEXT: arg string constant s

// Detail 2 (method prefix), detail 8 ($display's empty second argument, and a string literal that is not empty).
module top;
  logic [3:0] a = 4'd9;
  function automatic void note(input int x, input int y);
  endfunction
  task automatic tk(input int x);
  endtask
  class K;
    function void go(int n);
    endfunction
  endclass
  K obj = new;
  import "DPI-C" context function void probe();
  initial begin
    note(a, 5);
    tk(a + 1);
    obj.go(3);
    $display(a, , "s");
    probe();
    $finish;
  end
endmodule
