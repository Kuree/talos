// CLAUSE: tagged member
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef union tagged{int A;byte B;}U;U u;
initial begin
u=tagged A 7;if(u.A!=7)$fatal(1,"tagged member");
$display("PASS");$finish;
end
endmodule
