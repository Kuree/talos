// CLAUSE: bit queries fourstate
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [7:0] value;
initial begin

  value=8'b1x0z10xz;
  if($countbits(value,1'bx,1'bz)!=4 || $countones(value)!=2 || $isunknown(value)!=1)
    $fatal(1,"bit query counts=%0d ones=%0d unknown=%0d",$countbits(value,1'bx,1'bz),$countones(value),$isunknown(value));

$display("PASS");
$finish;
end
endmodule
