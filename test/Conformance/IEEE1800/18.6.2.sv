// CLAUSE: successful hooks
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x; int limit,pre,post,observed; constraint c {x==limit;} function void pre_randomize(); pre++; limit=7; endfunction function void post_randomize(); post++; observed=x; endfunction endclass
module top;
C c;
initial begin
c=new; if(!c.randomize() || c.x!=7 || c.pre!=1 || c.post!=1 || c.observed!=7) $fatal;
$display("PASS"); $finish;
end
endmodule
