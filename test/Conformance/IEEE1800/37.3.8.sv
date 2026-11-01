// CLAUSE: Managing transient objects: lifetime callbacks track a class object's creation, a frame's end with its variables still readable, and a thread's end
// XFAIL: *
// cbCreateObj, cbEndOfFrame and cbEndOfThread are not implemented; docs/vpi.md lists only lifecycle, delay and synchronization callback reasons.
// RUN: %clang -c -fPIC %S/Inputs/37.3.8/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: registered create=1
// CHECK: created class C t=0
// CHECK: registered frame=1
// CHECK: frame ended a=6 t=1
// CHECK: registered thread=1
// CHECK: thread ended t=2
// CHECK: done

module top;
class C; int v; endclass
C c;
import "DPI-C" context function void track_class();
import "DPI-C" context function void track_frame();
import "DPI-C" context function void track_thread();
task automatic body();
  int a = 5;
  track_frame();
  #1 a = 6;
endtask
initial begin
  track_class();
  c = new;
  body();
  fork
    begin track_thread(); #1; end
  join
  $display("done");
  $finish;
end
endmodule
