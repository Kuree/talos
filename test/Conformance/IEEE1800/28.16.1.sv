// CLAUSE: gate typical delay
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic a=0;wire y;buf #(1:3:5) g(y,a);
initial begin
#6;a=1;#2;if(y!==0)$fatal;#2;if(y!==1)$fatal;
$display("PASS");$finish;
end
endmodule
