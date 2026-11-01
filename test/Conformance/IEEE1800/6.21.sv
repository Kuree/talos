// CLAUSE: automatic concurrent task
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int count=0;task automatic t(int v);int local_v=v;#1;count+=local_v;endtask
initial begin
fork t(1);t(2);join if(count!=3)$fatal(1,"automatic task instances");
$display("PASS");$finish;
end
endmodule
