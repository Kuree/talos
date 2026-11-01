// CLAUSE: wait order same slot source order
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
event a,b; int outcome=99;
initial begin
fork begin wait_order(a,b) outcome=1; else outcome=0; end join_none #1; ->a; ->b; #1; if(outcome!=1) $fatal(1,"outcome=%0d",outcome);
$display("PASS"); $finish;
end

endmodule
