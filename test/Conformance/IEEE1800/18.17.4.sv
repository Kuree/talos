// CLAUSE: Repeat generates a production exactly its nonnegative count.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
automatic int count=0;
randsequence(main) main: repeat(0) bad repeat(3) good; bad:{$fatal(1,"zero repeat");}; good:{count++;}; endsequence
if(count!=3) $fatal(1,"count=%0d",count);
$display("PASS");
end
endmodule
