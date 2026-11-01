// CLAUSE: Intermodule path: vpi_handle_multi gives a path between an output and an input port, whose delays can be written, read back and take effect
// XFAIL: *
// vpi_put_delays is not implemented, so the probe does not link
// RUN: %clang -c -fPIC %S/Inputs/37.37/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiInterModPath
// CHECK: port o
// CHECK: port i
// CHECK: delays before rise=0 fall=0
// CHECK: delays after rise=5 fall=7
// CHECK: t=15 i=0101
// CHECK: t=37 i=0000

// Delays written through vpi_put_delays (38.32) are the path's actual delays: 5 for a change to 1, 7 for a change to 0.
`timescale 1ns/1ns
module drv(output wire [3:0] o, input wire [3:0] in);
  assign o = in;
endmodule
module rcv(input wire [3:0] i);
  always @(i) $display("t=%0t i=%b", $time, i);
endmodule
module top;
  logic [3:0] in = 0;
  wire [3:0] w;
  drv d(w, in);
  rcv r(w);
  import "DPI-C" context function void probe();
  initial begin
    #1 probe();
    #9 in = 4'b0101;
    #20 in = 4'b0000;
    #20 $finish;
  end
endmodule
