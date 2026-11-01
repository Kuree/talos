// CLAUSE: conditional guard
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; bit x,y,enable; covergroup cg; option.per_instance=1; cp: coverpoint x iff(enable) {bins zero={0}; bins one={1};} endgroup function new(); cg=new; endfunction endclass
module top;
C c;
initial begin
c=new; c.enable=0; c.x=0; c.cg.sample(); if(c.cg.cp.get_inst_coverage()!=0.0) $fatal; c.enable=1; c.cg.sample(); if(c.cg.cp.get_inst_coverage()!=50.0) $fatal;
$display("PASS"); $finish;
end
endmodule
