// CLAUSE: failure retains hooks
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; rand bit [3:0] x=7; int pre,post; constraint c {x==0; x==1;} function void pre_randomize(); pre++; endfunction function void post_randomize(); post++; endfunction endclass
module top;
C c;
initial begin
c=new; if(c.randomize()!=0 || c.x!=7 || c.pre!=1 || c.post!=0) $fatal(1,"failure x=%0d pre=%0d post=%0d",c.x,c.pre,c.post);
$display("PASS"); $finish;
end
endmodule
