// CLAUSE: sv_vpi_user.h codes match Annex M and classify live class, assertion, interface and variable objects
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/M/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: interface=601 longint=610 class var=615 bit=620 class obj=621 assert=686
// CHECK: object id nonzero=1
// Annex M gives each number on the CHECK line. The simulator must report the same codes for live objects.

interface bus;
endinterface
class widget;
  int id = 9;
endclass
module top;
  bit clk;
  bit b = 1;
  longint l = 5;
  widget w = new;
  bus i();
  check: assert property (@(posedge clk) 1'b1);
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
