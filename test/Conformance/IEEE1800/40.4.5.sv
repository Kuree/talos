// CLAUSE: Specifying current and next state signals in same declaration pragma recognition
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=fsm -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe

module top;
/* tool state_vector state */
logic[1:0] /* tool enum states */ state=0,next=0;
initial begin
#1;
$display("PASS");$finish;
end
endmodule
