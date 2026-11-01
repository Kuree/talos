// CLAUSE: Iterator: vpiIteratorType is the type asked for and vpiUse the reference handle, or NULL for a NULL reference
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.84/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: vpiIterator of nets: type=vpiNet use=top same=1 first=n
// CHECK: vpiIterator of ranges: type=vpiRange use=v same=1 first=vpiRange
// CHECK: vpiIterator of modules: type=vpiModule use=null first=top

module top;
wire n;
logic [3:0] v;
import "DPI-C" context function void probe();
initial begin
  probe();
  $finish;
end
endmodule
