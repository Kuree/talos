// CLAUSE: Ports: a port reports index, name, direction, size and type, its high and low connections carry the live value, and an unconnected port has a NULL vpiHighConn
// XFAIL: *
// On ports vpiExplicitName and vpiConnByName return vpiUndefined, and an unconnected "input logic" reads x as a variable where 23.2.2.3 makes it a net that reads z.
// RUN: %clang -c -fPIC %S/Inputs/37.14/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: t=1 port 0 name=a dir=input size=4 type=vpiPort scalar=0 vector=1 explicit=0 byname=1 high=0101 low=0101
// CHECK: t=1 port 1 name=b dir=output size=1 type=vpiPort scalar=1 vector=0 explicit=0 byname=1 high=1 low=1
// CHECK: t=1 port 2 name=ext dir=input size=2 type=vpiPort scalar=0 vector=1 explicit=1 byname=1 high=10 low=10
// CHECK: t=1 port 3 name=unc dir=input size=1 type=vpiPort scalar=1 vector=0 explicit=0 high=null low=z
// CHECK: t=2 port 0 name=a {{.*}} high=1010 low=1010
// CHECK: t=2 port 1 name=b {{.*}} high=0 low=0
// CHECK: port bits=4 type=vpiPortBit parent=a

module leaf(a, b, .ext(inner), unc);
input logic [3:0] a;
output logic b;
input logic [1:0] inner;
input logic unc;
assign b = a[0];
endmodule
module top;
logic [3:0] x = 4'b0101;
wire y;
logic [1:0] z = 2;
leaf u(.a(x), .b(y), .ext(z));
import "DPI-C" context function void show(int t);
import "DPI-C" context function void bits();
initial begin
  #1 show(1);
  x = 4'b1010;
  #1 show(2);
  bits();
  $finish;
end
endmodule
