// CLAUSE: strength format
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wire n;assign(pull0,pull1)n=1;
initial begin
#1;if($sformatf("%v",n)!="Pu1")$fatal;
$display("PASS");$finish;
end
endmodule
