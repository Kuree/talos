// CLAUSE: Class typespec: a specialization gives its class type, class defn, resolved parameters, members and specialized base; a built-in class has no defn
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.32/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiClassTypespec named=1 user=1 defn=P
// CHECK: param W=5 local=0
// CHECK: param L=7 local=1
// CHECK-DAG: var own
// CHECK-DAG: method m
// CHECK-DAG: constraint c
// CHECK: base defn=Base
// CHECK: base param B=6 local=0
// CHECK: mailbox mailbox=1 defn=null
// CHECK-DAG: specialization W=5
// CHECK-DAG: specialization W=8
// CHECK: specializations=2

module top;
  class Base #(int B = 1);
    int base_v;
  endclass
  class P #(int W = 3) extends Base #(W + 1);
    localparam int L = 7;
    rand int own;
    function void m(); endfunction
    constraint c { own > 0; }
  endclass
  P #(5) v;
  P #(8) v2;
  mailbox #(int) mb;
  import "DPI-C" context function void probe();
  initial begin probe(); $finish; end
endmodule
