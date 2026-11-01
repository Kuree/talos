// CLAUSE: cross counts
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; bit x,y,enable; covergroup cg; option.per_instance=1; cx: coverpoint x {bins zero={0}; bins one={1};} cy: coverpoint y {bins zero={0}; bins one={1};} pair: cross cx,cy; endgroup function new(); cg=new; endfunction endclass
module top;
C c; int covered,total; real r;
initial begin
c=new; c.x=0; c.y=1; c.cg.sample(); r=c.cg.pair.get_inst_coverage(covered,total); if(r!=25.0 || covered!=1 || total!=4) $fatal(1,"r=%0f bins=%0d/%0d",r,covered,total);
$display("PASS"); $finish;
end
endmodule
