// CLAUSE: polymorphic shallow copy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; static B latest;
function new(); latest=this; endfunction
virtual function int kind(); return 1; endfunction endclass
class D extends B; function int kind(); return 2; endfunction endclass
module top; initial begin
D d; d=new; if(B::latest!=d || B::latest.kind()!=2) $fatal(1,"constructor published identity");
$display("PASS"); $finish; end endmodule
