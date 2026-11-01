// CLAUSE: Interface task or function declaration: vpiAccessType separates extern from forkjoin, and a forkjoin task reaches every exporting module's task
// XFAIL: *
// vpi_iterate(vpiInterfaceTfDecl, interface) returns NULL, so no interface tf decl object exists, although the tasks themselves dispatch correctly.
// RUN: %clang -c -fPIC %S/Inputs/37.8/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: tf access=vpiExternAcc task=top.d0.put
// CHECK-DAG: tf access=vpiForkJoinAcc task=top.d0.ping task=top.d1.ping
// CHECK-DAG: tf access=vpiExternAcc function=top.d0.peek
// CHECK: got=5 hits=3 peek=8

interface bus;
extern task put(input int v);
extern function int peek();
extern forkjoin task ping();
modport both(export put, export peek, export ping);
modport pinged(export ping);
endinterface
module first(bus.both b);
task b.put(input int v); top.got = v; endtask
function int b.peek(); return 8; endfunction
task b.ping(); top.hits += 1; endtask
endmodule
module second(bus.pinged b);
task b.ping(); top.hits += 2; endtask
endmodule
module top;
int got, hits, peeked;
bus b();
first d0(b);
second d1(b);
import "DPI-C" context function void probe();
initial begin
  b.put(5);
  b.ping();
  peeked = b.peek();
  probe();
  $display("got=%0d hits=%0d peek=%0d", got, hits, peeked);
  $finish;
end
endmodule
