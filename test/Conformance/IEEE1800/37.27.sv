// CLAUSE: Named events: a named event reports name, lifetime, allocation and waiting processes, vpi_put_value triggers it, and event arrays give indexed elements
// XFAIL: *
// vpi_put_value on a named event does not toggle it (38.34): a NULL value_p reports "VPI write value is null" and vpiIntVal segfaults.
// RUN: %clang -c -fPIC %S/Inputs/37.27/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: event type=vpiNamedEvent name=e full=top.e auto=0 other-scheme=1 array-member=0 index=null typespec=vpiEventTypespec waiting=1
// CHECK: before hits=0
// CHECK: woke t=2
// CHECK: after hits=1
// CHECK: array type=vpiNamedEventArray full=top.ea element=top.ea[1] array-member=1 index=1
// CHECK: element wake=1

module top;
event e;
event ea[2:0];
int hits, element_hits;
always @e begin
  hits++;
  $display("woke t=%0d", $time);
end
always @(ea[1]) element_hits++;
import "DPI-C" context function void describe();
import "DPI-C" context function void fire();
import "DPI-C" context function void describe_array();
initial begin
  #1 describe();
  $display("before hits=%0d", hits);
  #1 fire();
  #1 $display("after hits=%0d", hits);
  describe_array();
  #1 $display("element wake=%0d", element_hits);
  $finish;
end
endmodule
