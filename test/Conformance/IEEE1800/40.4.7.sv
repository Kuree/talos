// CLAUSE: Pragmas in one-line comments pragma recognition
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=fsm -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;
logic[1:0] state=0;
// tool state_vector state
initial begin
#1;
$display("PASS");$finish;
end
endmodule
