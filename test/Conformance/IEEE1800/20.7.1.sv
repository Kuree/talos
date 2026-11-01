// CLAUSE: nested variable dimensions
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef int row[];row a[];
initial begin
a=new[2];a[0]=new[3];a[1]=new[4];if($size(a)!=2 || $size(a[1])!=4)$fatal;
$display("PASS");$finish;
end
endmodule
