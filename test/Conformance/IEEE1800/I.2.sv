// CLAUSE: dpi dynamic open array
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/I.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins Annex I (scope and time services): scope name round trip, user data store/fetch, time unit -9 and precision -12, and the current time 5 in the scope unit.
// CHECK: nm=top look=1 ud=1 tu=912 tm=5

module top;
  timeunit 1ns; timeprecision 1ps;
  import "DPI-C" context function string nm();
  import "DPI-C" context function int look();
  import "DPI-C" context function int ud();
  import "DPI-C" context function int tu();
  import "DPI-C" context function int tm();
  initial begin
    #5;
    $display("nm=%s look=%0d ud=%0d tu=%0d tm=%0d", nm(), look(), ud(), tu(), tm());
  end
endmodule
