// CLAUSE: Location independence
// SINCE: 0.1.0
// REQUIRES: native-elf
// RUN: mkdir -p %t.libs
// RUN: %clang -shared -fPIC %S/Inputs/J.3/helper.c -I%resource_dir/include -o %t.libs/helper.c.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -sv_root %t.libs -sv_lib helper.c -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int external_value();
initial begin
if(external_value()!=7)$fatal(1,"foreign library lookup");
$display("PASS");$finish;
end
endmodule
