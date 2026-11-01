// CLAUSE: repeat all x zero control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int hits=0;
initial begin

repeat(2'bxx) hits++;
if(hits!=0) $fatal(1,"hits=%0d",hits);

$display("PASS"); $finish;
end
endmodule
