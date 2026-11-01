// CLAUSE: A correctly defined explicit external constraint block can constrain its random property.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class Item; rand bit x; extern constraint k; endclass constraint Item::k {x==1;}
module top; initial begin
Item a; a=new; if(!a.randomize() || a.x!=1) $fatal(1,"extern");
$display("PASS"); end endmodule
