// CLAUSE: Modport: a modport reports its name, owning interface and io decls with their directions
// XFAIL: *
// vpi_iterate(vpiIODecl, modport) returns NULL, so a modport reports no io decls or directions.
// RUN: %clang -c -fPIC %S/Inputs/37.7/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: modport type=vpiModport name=target in=top.b req:input gnt:output
// CHECK-DAG: modport type=vpiModport name=initiator in=top.b gnt:input req:output

interface bus;
logic req, gnt;
modport target(input req, output gnt);
modport initiator(input gnt, output req);
endinterface
module top;
bus b();
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
