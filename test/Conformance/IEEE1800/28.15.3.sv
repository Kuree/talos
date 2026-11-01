// CLAUSE: supply net strength
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
supply0 a;supply1 b;
initial begin
#1;if(a!==0 || b!==1 || $sformatf("%v",a)!="Su0" || $sformatf("%v",b)!="Su1")$fatal;
$display("PASS");$finish;
end
endmodule
