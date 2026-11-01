// CLAUSE: Virtual interface: vpiActual follows the variable's current interface or modport and is NULL before assignment, vpiExpr gives the declared initializer, and arrays iterate by element
// XFAIL: *
// vpiDefName of an interface typespec returns NULL, and vpiExpr of a virtual interface variable with a declared initializer returns NULL (detail 1).
// RUN: %clang -c -fPIC %S/Inputs/37.29/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: v type=vpiVirtualInterfaceVar name=v full=top.v modport=0 typespec=vpiInterfaceTypespec def=SBus actual=null expr=null
// CHECK: v actual=top.s0 type=vpiInterface
// CHECK: v actual=top.s1 type=vpiInterface
// CHECK: init actual=top.s1 expr=top.s1
// CHECK: vm modport=1 def=phy actual=phy type=vpiModport
// CHECK: vifs=6 variables array=vpiArrayVar
// CHECK: through v addr=165

interface SBus;
logic [7:0] addr;
modport phy(input addr);
endinterface
module top;
SBus s0();
SBus s1();
virtual SBus v;
virtual SBus init = s1;
virtual SBus.phy vm;
virtual SBus va[2:0];
import "DPI-C" context function void describe();
import "DPI-C" context function void actual();
import "DPI-C" context function void rest();
initial begin
  describe();
  v = s0;
  actual();
  v = s1;
  actual();
  vm = s0.phy;
  v.addr = 8'hA5;
  rest();
  $display("through v addr=%0d", s1.addr);
  $finish;
end
endmodule
