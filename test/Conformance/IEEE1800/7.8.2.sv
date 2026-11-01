// CLAUSE: String-indexed associative array
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
int a[string];
string key="k";
initial begin
a[key]=7;
if(a["k"]!==7)$fatal;
$display("PASS");
end
endmodule
