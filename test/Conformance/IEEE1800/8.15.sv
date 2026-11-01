// CLAUSE: virtual super call is base member
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; int base_calls; virtual function int get(); base_calls++; return 1; endfunction endclass
class D extends B; int derived_calls;
function int get(); derived_calls++; return 10+super.get(); endfunction endclass
module top; initial begin
D d; B b; d=new; b=d; if(b.get()!=11 || d.base_calls!=1 || d.derived_calls!=1) $fatal(1,"super virtual member");
$display("PASS"); $finish; end endmodule
