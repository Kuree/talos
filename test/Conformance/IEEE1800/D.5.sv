// CLAUSE: $key and $nokey optional interface
// XFAIL: *
// The optional $key and $nokey system interface is not executable.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
$key("key.log");$nokey;
$display("PASS");$finish;
end
endmodule
