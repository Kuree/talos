// CLAUSE: escaped identifier
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int \wire ; int plain;
initial begin

  \wire = 9; \plain = 11;
  if (\wire !=9 || plain!=11) $fatal(1,"escaped identifier");

$display("PASS");
$finish;
end
endmodule
