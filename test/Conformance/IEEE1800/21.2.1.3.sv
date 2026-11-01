// CLAUSE: p unknown radix
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string text;
initial begin
text=$sformatf("%0d:%0d:%0d:%0d:%h:%h:%b",4'bxxxx,4'bzzzz,4'bx001,4'bz001,8'bxxxx0001,4'bx001,4'b10xz); $display("PRINT|value|%s|END",text); if(text!="x:z:X:Z:x1:X:10xz") $fatal;
$display("PASS"); $finish;
end
endmodule
