// RUN: talos -O0 --vpi=read -emit-sim --top=top %s -o %t.mlir
// RUN: FileCheck %s --implicit-check-not='simulation.vpi_typespec.decl {{.*}}hierarchy "top.u.word_t"' < %t.mlir
// A type parameter's effective type comes from vpiTypespec. Only an actual
// typedef introduces a vpiTypedefAlias layer (IEEE 1800-2023 37.25, 37.28).
// CHECK: simulation.vpi_typespec.decl {{.*}} hierarchy "top.u.byte_t" debug "byte_t"
module child #(parameter type word_t = logic [7:0]) (input word_t data);
  typedef word_t byte_t;
  byte_t value;
  assign value = data;
endmodule
module top;
  logic [7:0] data;
  child u(data);
endmodule
