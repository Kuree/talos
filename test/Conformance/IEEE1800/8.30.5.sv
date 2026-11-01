// CLAUSE: weak id inheritance
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class B; endclass
class D extends B; endclass
module top;
D a,b;
initial begin
a=new; b=new; if(weak_reference#(B)::get_id(null)!=0 || weak_reference#(B)::get_id(a)==0 || weak_reference#(B)::get_id(a)!=weak_reference#(D)::get_id(a) || weak_reference#(D)::get_id(a)==weak_reference#(D)::get_id(b)) $fatal;
$display("PASS"); $finish;
end
endmodule
