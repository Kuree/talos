// CLAUSE: postponed reevaluation
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: POSTPONED=7

module top;
  int x=0;
  initial begin
    $strobe("POSTPONED=%0d",x);
    x<=7;
    #1; $display("PASS"); $finish;
  end
endmodule
