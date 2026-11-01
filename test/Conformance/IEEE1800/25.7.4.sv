// CLAUSE: extern forkjoin invokes every task provider and joins them
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface I;int count=0;extern forkjoin task tick();modport M(ref count,export tick);endinterface
module Provider(I.M b);task b.tick();#1;b.count++;endtask endmodule
module top;I i();Provider a(i),b(i);
initial begin i.tick();if(i.count!=2 || $time!=1)$fatal;$display("PASS");$finish;end endmodule
