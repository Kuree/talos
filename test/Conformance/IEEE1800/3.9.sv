// CLAUSE: transitive package export
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

package A; int value=7; endpackage
package B; import A::value; export A::*; endpackage
module top;
  import B::*;
  initial begin if(value!=7) $fatal(1,"export value"); value=9; if(A::value!=9) $fatal(1,"export alias"); $display("PASS"); $finish; end
endmodule
