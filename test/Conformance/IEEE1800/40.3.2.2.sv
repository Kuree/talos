// CLAUSE: Maximum coverage stays constant as coverage changes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --coverage=toggle --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module dut;
  bit q=0;
endmodule
module top;
  dut d();
  int maximum;
  initial begin
    maximum=$coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d);
    if(maximum<=0)$fatal;
    #1; d.q=1; #1;
    if($coverage_get_max(`SV_COV_TOGGLE,`SV_COV_MODULE,d)!=maximum)$fatal;
    $display("PASS");
  end
endmodule
