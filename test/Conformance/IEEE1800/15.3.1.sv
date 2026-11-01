// CLAUSE: semaphore keys exceed initial
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
semaphore s;
initial begin
s=new(1); s.get(); s.put(3); if(s.try_get(3)<=0 || s.try_get()!=0) $fatal;
$display("PASS"); $finish;
end

endmodule
