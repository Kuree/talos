// CLAUSE: Structures and unions: vpiMember walks a struct or union's fields, vpiPacked and vpiTagged classify them, and an entire unpacked struct has no value
// XFAIL: *
// An unpacked tagged union variable makes the simulator exit 16 silently with VPI on, vpiTagged on an untagged struct or union is undefined, and vpi_put_value on a member is unimplemented.
// RUN: %clang -c -fPIC %S/Inputs/37.26/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: su type=vpiStructVar packed=0 tagged=0 size=2 member a=7 parent=top.su member b=5 parent=top.su
// CHECK: whole unpacked read error=1
// CHECK: sp type=vpiStructVar packed=1 tagged=0 size=8 value=163 member hi=10 parent=top.sp member lo=3 parent=top.sp
// CHECK: un type=vpiUnionVar packed=1 tagged=0 size=8 value=66 member w=66 parent=top.un member u=66 parent=top.un
// CHECK: ta type=vpiUnionVar packed=0 tagged=1
// CHECK: after put su.a=9

module top;
typedef struct { int a; logic [3:0] b; } us_t;
typedef struct packed { logic [3:0] hi; logic [3:0] lo; } ps_t;
typedef union packed { logic [7:0] w; logic [7:0] u; } pu_t;
typedef union tagged { int i; real r; } tu_t;
us_t su = '{7, 4'h5};
ps_t sp = '{4'hA, 4'h3};
pu_t un = 8'd66;
tu_t ta = tagged i 4;
import "DPI-C" context function void probe();
initial begin
  probe();
  #1 $display("after put su.a=%0d", su.a);
  $finish;
end
endmodule
