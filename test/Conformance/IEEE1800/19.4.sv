// CLAUSE: embedded counts
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; bit x,y,enable; covergroup cg; option.per_instance=1; cp: coverpoint x {bins zero={0}; bins one={1};} endgroup function new(); cg=new; endfunction endclass
module top;
C c; int covered,total; real r;
initial begin
c=new; c.cg.set_inst_name("packet"); c.x=0; c.cg.sample(); r=c.cg.cp.get_inst_coverage(covered,total); $display("STATE=%0f covered=%0d total=%0d",r,covered,total); if(r!=50.0 || covered!=1 || total!=2) $fatal; c.x=1; c.cg.sample(); if(c.cg.get_inst_coverage()!=100.0) $fatal;
$display("PASS"); $finish;
end
endmodule
