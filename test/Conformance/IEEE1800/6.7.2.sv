// CLAUSE: user net real resolution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}


package net_defs;
  function automatic real sum(input real drivers[]);
    sum=0.0; foreach(drivers[i]) sum+=drivers[i];
  endfunction
  nettype real real_sum with sum;
endpackage
module top;
  import net_defs::*;
  real_sum n; real a=1.25,b=2.5;
  assign n=a; assign n=b;
  initial begin #1; if(n!=3.75) $fatal(1,"n=%g",n); a=4.0; #1; if(n!=6.5) $fatal(1,"n=%g",n); $display("PASS"); $finish; end
endmodule
