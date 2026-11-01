// CLAUSE: An instance-targeted bind affects one selected instance and evaluates identifiers from its
// XFAIL: *
// Binding one parameterized instance fails the imported original-parameter-assignment verifier.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`timescale 1ns/1ps
package Count; int hits=0; endpackage
module Leaf #(parameter int K=1); endmodule
module Tap #(parameter int EXPECTED=0); localparam int VALUE=EXPECTED; initial Count::hits++; endmodule
module top; localparam int K=99; Leaf#(7) one(); Leaf#(9) two(); bind one Tap#(.EXPECTED(K)) tap();
initial begin #1; if(Count::hits!=1 || one.tap.VALUE!=7) $fatal(1,"single bind target"); $display("PASS"); $finish; end endmodule
