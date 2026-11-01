// CLAUSE: interface diamond symbol dispatch
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

interface class Root; parameter int N=7; pure virtual function int f(); endclass
interface class Left extends Root; endclass
interface class Right extends Root; endclass
interface class Diamond extends Left,Right; endclass
class C implements Diamond; virtual function int f(); return Diamond::N; endfunction endclass
module top;
C c; Diamond d; Root r;
initial begin
c=new; d=c; r=d; if(d.f()!=7 || r.f()!=7 || Diamond::N!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
