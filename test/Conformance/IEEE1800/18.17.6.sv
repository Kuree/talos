// CLAUSE: Return aborts only the current production and resumes the caller following it.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int trace=0;
randsequence(main) main:parent tail; parent:leaf middle; leaf:{trace=10*trace+1; return; trace=9;} bad; middle:{trace=10*trace+2;}; tail:{trace=10*trace+3;}; bad:{$fatal(1,"return suffix");}; endsequence
if(trace!=123) $fatal(1,"return trace=%0d",trace);
$display("PASS");
end
endmodule
