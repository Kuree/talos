// CLAUSE: Nettype declaration: a nettype reports its name, data type and vpiWith resolution function, an alias reports vpiNetTypedefAlias, and a net of it resolves through the function
// XFAIL: native
// vpi_get_value on a net of a user-defined real nettype returns 0 in native code while $display and bytecode see the resolved 4.
// RUN: %clang -c -fPIC %S/Inputs/37.23/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: nettype name=summed type=vpiRealTypespec with=resolve_sum alias=null
// CHECK-DAG: nettype name=again type=vpiRealTypespec with=resolve_sum alias=summed
// CHECK-DAG: nettype name=plain type=vpiRealTypespec with=null alias=null
// CHECK: declared=3
// CHECK: net summed value=4 nettype-net=1

module top;
function automatic real resolve_sum(input real driver[]);
  real total = 0;
  foreach (driver[i]) total += driver[i];
  return total;
endfunction
nettype real summed with resolve_sum;
nettype summed again;
nettype real plain;
summed n;
assign n = 1.5;
assign n = 2.5;
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
