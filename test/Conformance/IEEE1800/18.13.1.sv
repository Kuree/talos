// CLAUSE: Reusing an integral urandom seed reproduces the following sequence.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
int unsigned values[8]; int unsigned discarded; discarded=$urandom(12345); foreach(values[i]) values[i]=$urandom; discarded=$urandom(12345); foreach(values[i]) if($urandom!=values[i]) $fatal(1,"seed replay %0d",i);
$display("PASS");
end
endmodule
