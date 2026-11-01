// CLAUSE: input dynamic array copy
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  typedef int Row[]; Row a[2];
  task automatic modify(input Row b[2]); b[0][0]=99; endtask

initial begin

  a[0]='{1,2}; a[1]='{3}; modify(a);
  if(a[0][0]!=1) $fatal(1,"input argument aliased nested array=%p",a);

$display("PASS");
$finish;
end
endmodule
