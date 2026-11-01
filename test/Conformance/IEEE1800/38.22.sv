// CLAUSE: vpi_handle_multi returns the vpiInterModPath between an output port and an input port of the same size
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.22/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiInterModPath
// CHECK-NEXT: port0=top.src.o
// CHECK-NEXT: port1=top.dst.i
// CHECK-NEXT: ports=2 same_again=1
// CHECK-NEXT: wider=null

module source(output logic [3:0] o);
assign o = 4'h5;
endmodule
module sink(input logic [3:0] i, input logic [7:0] wide);
endmodule
module top;
wire [3:0] w;
source src(.o(w));
sink dst(.i(w), .wide(8'h0));
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
