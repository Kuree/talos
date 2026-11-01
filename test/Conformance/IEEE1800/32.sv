// CLAUSE: SDF annotations
// XFAIL: *
// The filename comes from a run-time plusarg inside an if; static SDF annotation cannot fold it and no run-time SDF parser exists.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe +sdf=%S/Inputs/32/fixtures/delay.sdf
// CHECK-DAG: {{^PASS$}}

module delayed_cell(input wire a,output wire y);
  timeunit 1ns; timeprecision 1ns;
  assign y=a; specify(a=>y)=1; endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  logic a=0; wire y; string path;
  delayed_cell d(a,y);
  initial begin
    if(!$value$plusargs("sdf=%s",path)) path="fixtures/delay.sdf";
    $sdf_annotate(path,d);
    #5; a=1; #1; if(y!==0) $fatal(1,"annotation failed");
    #3; if(y!==1) $fatal(1,"annotated path update missing");
    $display("PASS"); $finish;
  end
endmodule
