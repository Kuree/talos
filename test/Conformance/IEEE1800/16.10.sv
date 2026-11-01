// CLAUSE: local variable
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
bit clk, reset, one=1, zero;
int passes, failures, match_hits;

property p; int saved; (one,saved=7) ##1 saved==7; endproperty
ap: assert property (@(posedge clk) disable iff(reset) p) passes++;
    else failures++;
initial begin
  repeat(6) begin #1; clk=1; #1; clk=0; end
  reset=1; #1;
  if(passes==0 || failures!=0) $fatal(1,"passes=%0d failures=%0d",passes,failures);
  $display("PASS"); $finish;
end
endmodule
