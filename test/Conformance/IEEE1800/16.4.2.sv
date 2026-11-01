// CLAUSE: deferred report flush on event resume
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top; event wake; int passes=0,failures=0;
function void record(input bit ok); if(ok) passes++; else failures++; endfunction
initial begin
 fork begin #0; ->wake; end join_none
 assert #0(0) record(1); else record(0);
 @wake;
 assert #0(1) record(1); else record(0);
 #1; if(passes!=1 || failures!=0) $fatal(1,"passes=%0d failures=%0d",passes,failures); $display("PASS"); $finish;
end
endmodule
