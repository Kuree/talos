// CLAUSE: sample arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; covergroup cg with function sample(bit value); option.per_instance=1; cp: coverpoint value {bins zero={0}; bins one={1};} endgroup function new(); cg=new; endfunction endclass
module top;
C c;
initial begin
c=new; c.cg.sample(0); if(c.cg.cp.get_inst_coverage()!=50.0) $fatal; c.cg.sample(1); if(c.cg.cp.get_inst_coverage()!=100.0) $fatal;
$display("PASS"); $finish;
end
endmodule
