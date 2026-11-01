// CLAUSE: vpi_put_delays replaces a primitive's delays: the output changes at the new delays and vpi_get_delays reads them back
// XFAIL: *
// The runtime has no vpi_put_delays (undefined symbol at link).
// RUN: %clang -c -fPIC %S/Inputs/38.32/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: read back 5 7
// CHECK-NEXT: o=1 t=15
// CHECK-NEXT: o=0 t=27

module top;
timeunit 1ns; timeprecision 1ns;
logic a = 0;
wire o;
buf #(1, 1) g(o, a);
always @(o) if (o !== 1'bx) $display("o=%b t=%0t", o, $time);
import "DPI-C" context function void probe();
initial begin
  #2 probe();
  #8 a = 1;
  #10 a = 0;
  #20 $finish;
end
endmodule
