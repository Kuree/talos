// CLAUSE: semaphore derived class
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

class S extends semaphore; endclass
module top;
S s;
initial begin
s=new;
$display("PASS"); $finish;
end

endmodule
