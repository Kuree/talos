// CLAUSE: vpi_flush returns 0 and pushes buffered vpi_printf text to the output channel
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: partial line, then an unbuffered write
// CHECK: flush=0

module top;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
