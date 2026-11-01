// CLAUSE: interconnect terminal
// XFAIL: *
// The frontend rejects an interconnect net connected to built-in primitive terminals.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
interconnect n;wire y;buf a(n,1'b1),b(y,n);
initial begin
#1;if(y!==1)$fatal;
$display("PASS");$finish;
end
endmodule
