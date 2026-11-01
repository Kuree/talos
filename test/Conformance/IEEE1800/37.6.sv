// CLAUSE: Interface: an interface instance reports its type, definition, modports, cont assigns and processes, and vpiIndex only inside an instance array
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.6/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: instance type=vpiInterface name=b def=bus full=top.b index=null
// CHECK: modports=2 contassigns=1 processes=1 children=1
// CHECK: element full=top.arr[1] index=1
// CHECK: value gnt=1

interface sub; endinterface
interface bus;
logic req, gnt;
sub inner();
assign gnt = req;
initial req = 1;
modport target(input req, output gnt);
modport initiator(input gnt, output req);
endinterface
module top;
bus b();
bus arr[1:0]();
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
