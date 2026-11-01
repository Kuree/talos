// CLAUSE: Randcase choices use the thread RNG and replay from saved state.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin
process p; string saved; int values[8]; int value; p=process::self(); p.srandom(180); saved=p.get_randstate(); foreach(values[i]) begin randcase 1:value=1; 2:value=2; endcase values[i]=value; end p.set_randstate(saved); foreach(values[i]) begin randcase 1:value=1; 2:value=2; endcase if(value!=values[i]) $fatal(1,"randcase replay"); end
$display("PASS");
end
endmodule
