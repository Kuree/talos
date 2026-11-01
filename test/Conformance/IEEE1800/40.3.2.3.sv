// CLAUSE: Coverage count increases when a bit sees both values
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
    #1;
    if($coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d)!=0)$fatal;
    d.q=1; #1;
    if($coverage_get(`SV_COV_TOGGLE,`SV_COV_MODULE,d)!=1)$fatal;
    $display("PASS");
  end
endmodule
