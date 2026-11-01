// CLAUSE: A registered VPI system function executes its call callback
// XFAIL: *
// NOTE: Registered VPI system functions are rejected during compilation.
// RUN: %clang -c -fPIC %S/Inputs/36.9/systf.c -I%resource_dir/include -o %t.systf.c.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier --vpi=full %s %t.systf.c.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;

initial begin
if($conformance()!=7)$fatal(1,"VPI system function");
$display("PASS");$finish;
end
endmodule
