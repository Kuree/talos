// CLAUSE: Generates: gen scope array size and by-index access; vpiIndex, vpiArrayMember, genvar parameter, variables; vpiImplicitDecl when unnamed
// XFAIL: *
// vpiImplicitDecl is undefined on a gen scope and vpiVariables lists nothing in one; size, vpiIndex, vpiArrayMember and vpiParameter work.
// RUN: %clang -c -fPIC %S/Inputs/37.85/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: array vpiGenScopeArray name=gb full=top.gb size=3
// CHECK: element vpiGenScope full=top.gb[1] index=1 member=1 implicit=0 g=1 v=10
// CHECK: named vpiGenScope full=top.nb member=0 implicit=0
// CHECK: unnamed vpiGenScope full=top.genblk3 member=0 implicit=1

module top;
for (genvar g = 0; g < 3; g++) begin : gb
  int v = g * 10;
end
if (1) begin : nb
  int w;
end
if (1) begin
  int u;
end
import "DPI-C" context function void probe();
initial begin
  #1 probe();
  $finish;
end
endmodule
