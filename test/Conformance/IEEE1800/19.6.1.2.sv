// CLAUSE: cross with matches count
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; timeunit 1ns; timeprecision 1ns;
bit [1:0] x,y; covergroup G ; option.per_instance=1; a: coverpoint x {bins low={0,1}; bins high={2,3};} b: coverpoint y {bins all={0,1};} X: cross a,b {option.cross_retain_auto_bins=0; bins diagonal=X with (a==b) matches 2;} endgroup
G c,c2;
int n,d; real r;
initial begin
c=new; x=0;y=1;c.sample(); r=c.X.get_inst_coverage(n,d); $display("COVER|c.X|%0f|%0d|%0d",r,n,d); if(r<100-0.00001 || r>100+0.00001 || n!=1 || d!=1) $fatal(1,"coverage c.X");

$display("PASS"); $finish;
end
endmodule
