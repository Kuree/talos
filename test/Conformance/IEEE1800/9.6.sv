// CLAUSE: Waiting for spawned processes to terminate
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier  %s  -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int x=0;
initial begin
fork begin #1;x=1;end join_none wait fork;if(x!=1)$fatal(1,"wait fork");
$display("PASS");$finish;
end
endmodule
