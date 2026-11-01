// CLAUSE: Production if/else selects by the current Boolean expression.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace=0; automatic bit flag=0;
randsequence(main) main: select {flag=1;} select; select:if(flag) yes else no; yes:{trace=10*trace+1;}; no:{trace=10*trace+2;}; endsequence
if(trace!=21) $fatal(1,"if=%0d",trace);
$display("PASS");
end
endmodule
