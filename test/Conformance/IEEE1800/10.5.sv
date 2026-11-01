// CLAUSE: variable initializer not continuous
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic src=0; logic dst=src;
initial begin
#1; src=1; #1; if(dst!==0) $fatal(1,"initializer followed source");
$display("PASS"); $finish;
end
endmodule
