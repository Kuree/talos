// CLAUSE: forward subroutine
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
function int f();return g();endfunction function int g();return 3;endfunction
initial begin
if(f()!=3)$fatal(1,"forward function name");
$display("PASS");$finish;
end
endmodule
