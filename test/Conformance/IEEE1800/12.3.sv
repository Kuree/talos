// CLAUSE: statement syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;

initial begin
if(1)begin end else begin end
$display("PASS");$finish;
end
endmodule
