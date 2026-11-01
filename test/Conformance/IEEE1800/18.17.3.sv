// CLAUSE: Case uses the first matching item and a default for unmatched values.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace=0; automatic int selector=2;
randsequence(main) main: select {selector=7;} select; select:case(selector) 1,2:a; 2:bad; default:b; endcase; a:{trace=10*trace+1;}; b:{trace=10*trace+2;}; bad:{$fatal(1,"later match");}; endsequence
if(trace!=12) $fatal(1,"case=%0d",trace);
$display("PASS");
end
endmodule
