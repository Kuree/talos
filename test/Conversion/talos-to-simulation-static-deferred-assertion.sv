// RUN: talos -emit-slang %s | FileCheck %s --check-prefix=SLANG
// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 16.4.3: a static deferred assertion is treated as if it were
// contained in an always_comb procedure, labeled or not. A plain always would
// never suspend. A static concurrent assertion remains an always procedure.
module top(input int a, input int b);
  a1: assert #0 (a == b);
  cover final (a != b);
  a2: assert property (@(posedge a[0]) b[0]);
endmodule

// SLANG-COUNT-2: slang.symbol.procedural_block {{.*}}procedure_kind = 3
// SLANG: slang.symbol.procedural_block {{.*}}procedure_kind = 2

// CHECK-COUNT-2: simulation.code_unit.decl {{[0-9]+}} in {{[0-9]+}} always_comb hierarchy "top.$code_unit_
// CHECK: simulation.code_unit.decl {{[0-9]+}} in {{[0-9]+}} always hierarchy "top.$code_unit_
