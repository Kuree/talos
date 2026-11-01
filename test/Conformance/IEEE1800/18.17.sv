// CLAUSE: Successive production items execute in source order.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace=0;
randsequence(main) main: a b c; a:{trace=10*trace+1;}; b:{trace=10*trace+2;}; c:{trace=10*trace+3;}; endsequence
if(trace!=123) $fatal(1,"order=%0d",trace);
$display("PASS");
end
endmodule
