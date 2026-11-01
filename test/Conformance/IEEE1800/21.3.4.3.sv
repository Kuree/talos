// CLAUSE: sscanf width suppression partial
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int n,decimal,other; logic [7:0] hex_value;
initial begin
n=$sscanf(" 17 skip ABCtail","%d %*s %2h",decimal,hex_value); if(n!=2 || decimal!=17 || hex_value!==8'hab) $fatal; other=99; n=$sscanf("9X","%d:%d",decimal,other); if(n!=1 || decimal!=9 || other!=99) $fatal;
$display("PASS"); $finish;
end
endmodule
