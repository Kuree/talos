// CLAUSE: logical four state truth
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] a,b,zero;
initial begin
a=4'b1x00; b=4'b0x00; zero=0; if(!a!==1'b0 || !b!==1'bx || (a && b)!==1'bx || (zero && b)!==0 || (a || b)!==1 || (a -> b)!==1'bx || (zero -> b)!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
