// CLAUSE: constant function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
function automatic int f(int n);return n+1;endfunction localparam N=f(3);logic[N-1:0]a;
initial begin
if($bits(a)!=4)$fatal(1,"constant function");
$display("PASS");$finish;
end
endmodule
