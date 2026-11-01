// CLAUSE: dynamic array delete
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[];
initial begin
a=new[2];a.delete();
if(a.size()!=0)$fatal(1,"delete");
$display("PASS");$finish;
end
endmodule
