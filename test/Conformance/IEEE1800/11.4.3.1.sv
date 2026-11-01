// CLAUSE: sizing mixed sign unsigned
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic signed [3:0] s; logic [7:0] u,both; logic signed [7:0] ss;
initial begin
s=-2; u=1; both=s+u; ss=s+s; if(both!=15 || ss!=-4) $fatal(1,"mixed=%0d signed=%0d",both,ss);
$display("PASS"); $finish;
end
endmodule
