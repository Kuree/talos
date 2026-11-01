// CLAUSE: severity warning
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
$warning("probe warning");
$display("PASS");$finish;
end
endmodule
