// CLAUSE: reduce width
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] a[]; logic [3:0] v;
initial begin

  a='{4'b10xz,4'b0101}; v=a.and();
  if(v!==4'b000x) $fatal(1,"and actual=%b",v);
  v=a.or(); if(v!==4'b11x1) $fatal(1,"or actual=%b",v);
  v=a.xor(); if(v!==4'b11xx) $fatal(1,"xor actual=%b",v);
  v=a.sum(); if(v!==4'bxxxx) $fatal(1,"sum actual=%b",v);

$display("PASS");
$finish;
end
endmodule
