// CLAUSE: MOS switches
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic data=1'bz; wire a,b,c,d; nmos n(a,data,1'b1); pmos p(b,data,1'b0); rnmos r(c,data,1'b1); rpmos s(d,data,1'b0);
initial begin
#1; if(a!==1'bz || b!==1'bz || c!==1'bz || d!==1'bz) $fatal; data=1; #1; if(a!==1 || b!==1 || c!==1 || d!==1) $fatal; data=0; #1; if(a!==0 || b!==0 || c!==0 || d!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
