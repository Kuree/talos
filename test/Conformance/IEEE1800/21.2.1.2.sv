// CLAUSE: decimal width pad
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
initial begin : test
string text; text=$sformatf("%3d",8'd5); $display("TEXT=|%s|",text); if(text!="  5")$fatal(1,"RADIX_FORMAT");
$display("PASS"); $finish;
end endmodule
