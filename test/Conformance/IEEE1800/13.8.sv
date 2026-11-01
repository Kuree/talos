// CLAUSE: parameterized static method
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
class C #(type T=int); static function T same(T value); return value; endfunction endclass
initial begin
if(C#(int)::same(7)!=7 || C#(string)::same("hi")!="hi") $fatal;
$display("PASS"); $finish;
end

endmodule
