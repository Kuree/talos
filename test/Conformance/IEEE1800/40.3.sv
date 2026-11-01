// CLAUSE: toggle coverage control and query
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=toggle -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
 bit q=0;
 initial begin
  void'($coverage_control(752,23,10,top));
  void'($coverage_control(750,23,10,top));
  #1 q=1;#1 q=0;#1;
  if($coverage_get(23,10,top)!=2) $fatal(1,"coverage count");
  void'($coverage_control(751,23,10,top));
  #1 q=1;#1;
  if($coverage_get(23,10,top)!=2) $fatal(1,"stop coverage");
  $display("PASS");$finish;
 end
endmodule
