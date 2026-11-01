// CLAUSE: transition sequence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; bit x,y,enable; covergroup cg; option.per_instance=1; cp: coverpoint x {bins roundtrip=(0=>1=>0);} endgroup function new(); cg=new; endfunction endclass
module top;
C c;
initial begin
c=new; c.x=0; c.cg.sample(); c.x=1; c.cg.sample(); if(c.cg.cp.get_inst_coverage()!=0.0) $fatal; c.x=0; c.cg.sample(); if(c.cg.cp.get_inst_coverage()!=100.0) $fatal;
$display("PASS"); $finish;
end
endmodule
