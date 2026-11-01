// CLAUSE: event triggered lifetime
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
event e;
initial begin

  ->e;
  if(!e.triggered) $fatal(1,"event not persistent in Active");
  #0; if(!e.triggered) $fatal(1,"event not persistent in Inactive");
  #1; if(e.triggered) $fatal(1,"event persists into next time slot");

$display("PASS");
$finish;
end
endmodule
