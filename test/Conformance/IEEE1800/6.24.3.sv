// CLAUSE: bitstream fixed size error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
typedef byte bytes_t[3]; bytes_t a;
initial begin
a=bytes_t'(32'h12345678);
$display("PASS"); $finish;
end
endmodule
