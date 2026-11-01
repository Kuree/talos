// CLAUSE: Reversing the two state guard conjuncts does not change the required suppression of a null
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class State; bit value; endclass class Item; rand bit x; bit enabled; State state; constraint k {if(enabled && state.value) x==1;} endclass
module top; initial begin
Item a; a=new; if(!a.randomize()) $fatal(1,"false first");
$display("PASS"); end endmodule
