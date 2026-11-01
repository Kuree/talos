// CLAUSE: initial once always repeat
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ps;

int once=0, ticks=0;
initial once++;
always #1 ticks++;
initial begin
  #2.5;
  if(once!=1 || ticks!=2) $fatal(1,"once=%0d ticks=%0d",once,ticks);
  #1;
  if(once!=1 || ticks!=3) $fatal;
  $display("PASS"); $finish;
end

endmodule
