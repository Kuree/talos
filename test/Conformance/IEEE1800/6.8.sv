// CLAUSE: new unknown case equality
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] a[];
initial begin

  a=new[1];
  $display("value=%b equal_to_X=%b",a[0],a[0]===4'hx);
  if(a[0] !== 4'hx) $fatal(1,"new element must case-match X");

$display("PASS");
$finish;
end
endmodule
