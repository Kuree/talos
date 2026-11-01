// CLAUSE: vpi_user.h codes match the Annex K listing and classify live objects
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/K.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type codes module=32 net=36 reg=48 integer=25 parameter=41
// CHECK: property codes type=1 name=2 fullname=3 size=4 defname=9
// CHECK: format codes bin=1 int=6
// CHECK: net size=4 value=1010
// Annex K gives each number on the CHECK lines. The simulator must report the same codes for live objects.

module top;
  wire [3:0] w = 4'b1010;
  reg r = 1;
  integer i = 5;
  parameter P = 3;
  import "DPI-C" context function void probe();
  initial begin
    #1 probe();
    $finish;
  end
endmodule
