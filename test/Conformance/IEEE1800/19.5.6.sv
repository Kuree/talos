// CLAUSE: illegal values excluded
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; timeunit 1ns; timeprecision 1ns;
bit [1:0] x; covergroup G ; option.per_instance=1; cp: coverpoint x {bins normal[]={0,1,2}; illegal_bins bad={1};} endgroup
G c,c2;
int n,d; real r;
initial begin
c=new; x=0; c.sample(); x=2; c.sample(); r=c.cp.get_inst_coverage(n,d); $display("COVER|c.cp|%0f|%0d|%0d",r,n,d); if(r<100-0.00001 || r>100+0.00001 || n!=2 || d!=2) $fatal(1,"coverage c.cp");

$display("PASS"); $finish;
end
endmodule
