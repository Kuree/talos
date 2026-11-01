// CLAUSE: Range endpoints are inclusive, reversed endpoints are accepted, and singleton ranges are e
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
int unsigned value; repeat(16) begin value=$urandom_range(3,10); if(value<3 || value>10) $fatal(1,"range=%0d",value); if($urandom_range(0,0)!=0 || $urandom_range(32'hffffffff,32'hffffffff)!=32'hffffffff) $fatal(1,"singletons"); end
$display("PASS");
end
endmodule
