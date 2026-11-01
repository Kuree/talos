// CLAUSE: Overview
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import std::*;process p;
initial begin
p=process::self();if(p==null)$fatal(1,"std package");
$display("PASS");$finish;
end
endmodule
