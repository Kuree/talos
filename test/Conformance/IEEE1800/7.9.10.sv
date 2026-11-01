// CLAUSE: assoc argument
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
function int read(input int a[int]);return a[3];endfunction int a[int];
initial begin
a[3]=7;if(read(a)!=7)$fatal(1,"associative argument");
$display("PASS");$finish;
end
endmodule
