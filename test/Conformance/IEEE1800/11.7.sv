// CLAUSE: signed expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic signed[7:0]s;
initial begin
s=$signed(4'b1100);if(s!=-4)$fatal(1,"signed extension");
$display("PASS");$finish;
end
endmodule
