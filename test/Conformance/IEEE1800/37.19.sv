// CLAUSE: Variable select: an element selected from an array var reports its parent, index, size, value and vpiConstantSelect, and a run-time index follows the index variable
// XFAIL: *
// No vpiVarSelect object exists: vpiRhs of "assign y = mem[i]" returns NULL, and vpi_put_value on an array element reports "indexed VPI writes require selected-state scheduling support".
// RUN: %clang -c -fPIC %S/Inputs/37.19/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: constant type=vpiVarSelect full=top.mem[2] parent=top.mem size=8 constant=1 index=2 value=170
// CHECK: varying type=vpiVarSelect parent=top.mem size=8 constant=0 index=1 value=187
// CHECK: varying type=vpiVarSelect parent=top.mem size=8 constant=0 index=3 value=204
// CHECK: put mem[2]=7

module top;
logic [7:0] mem [3:0];
int idx = 1;
wire [7:0] by_const, by_var;
assign by_const = mem[2];
assign by_var = mem[idx];
import "DPI-C" context function void show(string which, string path);
import "DPI-C" context function void put();
initial begin
  mem[1] = 8'hBB;
  mem[2] = 8'hAA;
  mem[3] = 8'hCC;
  #1 show("constant", "by_const");
  show("varying", "by_var");
  idx = 3;
  #1 show("varying", "by_var");
  put();
  #1 $display("put mem[2]=%0d", mem[2]);
  $finish;
end
endmodule
