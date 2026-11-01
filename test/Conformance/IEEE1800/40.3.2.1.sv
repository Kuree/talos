// CLAUSE: Reset clears collected toggle coverage
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --coverage=toggle --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module dut;
  bit q=0;
endmodule
module top;
  dut d();
  initial begin
    #1; d.q=1; #1;
    if($coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d)<=0)$fatal;
    if($coverage_control(`SV_COV_RESET,`SV_COV_TOGGLE,`SV_COV_MODULE,d)!=`SV_COV_OK)$fatal;
    if($coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d)!=0)$fatal;
    $display("PASS");
  end
endmodule
