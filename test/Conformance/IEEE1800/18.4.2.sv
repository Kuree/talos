// CLAUSE: randc full cycles
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class C; randc bit [1:0] x; endclass
module top;
C c; bit [3:0] seen;
initial begin
c=new; repeat(2) begin seen=0; repeat(4) begin if(!c.randomize() || seen[c.x]) $fatal(1,"randc repeated"); seen[c.x]=1; end if(seen!=4'hf) $fatal; end
$display("PASS"); $finish;
end
endmodule
