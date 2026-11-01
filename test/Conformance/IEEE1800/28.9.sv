// CLAUSE: CMOS/RCMOS conduct if either valid NMOS or PMOS path is on, and becomeZ when both paths ar
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic nc=1,pc=1,data=1; wire a,b; cmos c(a,data,nc,pc); rcmos r(b,data,nc,pc);
initial begin
#1; if(a!==1 || b!==1) $fatal; nc=0; pc=0; #1; if(a!==1 || b!==1) $fatal; pc=1; #1; if(a!==1'bz || b!==1'bz) $fatal; nc=1; #1; if(a!==1 || b!==1) $fatal;
$display("PASS"); $finish;
end
endmodule
