// CLAUSE: Memory: vpiMemory and vpiMemoryWord return reg array and reg objects, and a word reports its bounds, index and value
// XFAIL: *
// vpi_iterate(vpiMemoryWord) returns NULL, and vpi_put_value on a memory word reports "indexed VPI writes require selected-state scheduling support".
// RUN: %clang -c -fPIC %S/Inputs/37.20/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: memory reg-array=1 name=m is-memory=1 size=4 left=4 right=1
// CHECK: words=4 reg=1
// CHECK: word full=top.m[2] left=7 right=0 size=8 index=2 parent=top.m value=90
// CHECK: put m[3]=66

module top;
reg [7:0] m [4:1];
import "DPI-C" context function void probe();
initial begin
  m[2] = 8'h5A;
  probe();
  #1 $display("put m[3]=%0d", m[3]);
  $finish;
end
endmodule
