// CLAUSE: equivalent types
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef bit signed[7:0] B;B b;function automatic void put(ref byte v);v=7;endfunction
initial begin
put(b);if(b!=7)$fatal(1,"equivalent ref type");
$display("PASS");$finish;
end
endmodule
