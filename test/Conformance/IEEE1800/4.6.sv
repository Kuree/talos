// CLAUSE: inactive before nba
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [15:0] x;
initial begin

  x=0; x<=16'h1234; x[7:0]<=8'h56; x[11:4]<=8'h78;
  #1;
  if (x !== 16'h1786) $fatal(1,"source order actual=%h",x);

$display("PASS");
$finish;
end
endmodule
