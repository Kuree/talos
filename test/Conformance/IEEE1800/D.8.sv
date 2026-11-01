// CLAUSE: $reset, $reset_count, and $reset_value optional interface
// XFAIL: *
// The optional $reset, $reset_count, and $reset_value system interface is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if($reset_count()!=0)$fatal(1,"initial reset count");
$display("PASS");$finish;
end
endmodule
