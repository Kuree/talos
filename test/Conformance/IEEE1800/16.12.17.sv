// CLAUSE: recursive property
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
  bit clk=0,done=0;
  always #5 clk=~clk;
  property eventually_done;
    @(posedge clk) done or (1'b1 |=> eventually_done);
  endproperty
  p: assert property (eventually_done) else $fatal(1,"recursive property failed");
  initial begin #12; done=1; #14; $display("PASS"); $finish; end
endmodule
