// CLAUSE: Interface typespec: a virtual interface typedef reports name, definition, parameter assignments and vpiIsModPort, and a modport's typespec names the modport and has the interface as parent
// XFAIL: *
// typedef and variable typespecs report def=(null) instead of the interface and modport definitions
// RUN: %clang -c -fPIC %S/Inputs/37.30/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: typedef SB16 type=vpiInterfaceTypespec def=SBus modport=0 parent=null param WIDTH=16
// CHECK-DAG: typedef SBphy type=vpiArrayTypespec elem=vpiInterfaceTypespec def=phy modport=1 parent=SBus param WIDTH=32
// CHECK: typedefs=2
// CHECK: var type=vpiInterfaceTypespec def=SBus name=SB16

interface SBus #(parameter WIDTH = 8);
logic req, grant;
logic [WIDTH-1:0] addr;
wire [WIDTH-1:0] data;
modport phy(input addr, inout data);
endinterface
module top;
parameter SIZE = 4;
typedef virtual SBus#(16) SB16;
typedef virtual SBus#(32).phy SBphy [1:SIZE];
SBus#(16) b16();
SBus#(32) b32();
SB16 v = b16;
SBphy w;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
