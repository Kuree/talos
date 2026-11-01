// CLAUSE: Weights are evaluated for each selected production; zero-weight choices cannot occur.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace=0; automatic bit flag=0;
randsequence(main) main: choose choose; choose:a:=(1-flag)|b:=(flag); a:{trace=10*trace+1; flag=1;}; b:{trace=10*trace+2;}; endsequence
if(trace!=12) $fatal(1,"weights=%0d",trace);
$display("PASS");
end
endmodule
