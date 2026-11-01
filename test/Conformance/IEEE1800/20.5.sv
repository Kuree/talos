// CLAUSE: real bit roundtrip
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
real r; shortreal s; logic [63:0] rb; logic [31:0] sb;
initial begin
r=1.5; s=2.5; rb=$realtobits(r); sb=$shortrealtobits(s); if(rb!=64'h3ff8000000000000 || sb!=32'h40200000 || $bitstoreal(rb)!=r || $bitstoshortreal(sb)!=s) $fatal;
$display("PASS"); $finish;
end
endmodule
