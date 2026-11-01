// CLAUSE: A name forwarded through multiple package exports keeps its original declaration.
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
package A; typedef bit[3:0] Nibble; endpackage
package B; import A::Nibble; export *::*; endpackage
package C; import B::*; export B::Nibble; endpackage
module top; import C::*; Nibble value; initial begin value=4'ha; if($bits(value)!=4 || value!=10) $fatal(1,"transitive export"); $display("PASS"); $finish; end endmodule
