// CLAUSE: chandle
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/6.14/handle.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function chandle ptr();chandle h;
initial begin
h=ptr();if(h==null)$fatal(1,"chandle");
$display("PASS");$finish;
end
endmodule
