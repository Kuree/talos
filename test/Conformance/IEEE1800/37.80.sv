// CLAUSE: Callback: vpiCallback iterates an object's callbacks, or those on no object for NULL; vpi_get_cb_info returns what was registered
// XFAIL: *
// cbValueChange is not implemented (docs/vpi.md admits it), so no callback exists on an object to iterate; the NULL iteration works.
// RUN: %clang -c -fPIC %S/Inputs/37.80/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: on v: vpiCallback reason=cbValueChange obj=v user=watch-v
// CHECK: on v: count=1
// CHECK: on NULL: vpiCallback reason=cbEndOfSimulation obj=null user=at-end
// CHECK: on NULL: count=1
// CHECK: fired watch-v value=1
// CHECK: fired at-end

module top;
int v;
import "DPI-C" context function void probe();
initial begin
  probe();
  #1 v = 1;
  #1 $finish;
end
endmodule
