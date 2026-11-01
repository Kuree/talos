// RUN: talos --coverage=functional -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 19.6.1.3: a cross defines CrossValType and CrossQueueType for
// its bin functions. They have no VPI object, so a local of those types records
// no typespec that the design does not declare.
module top;
  bit x, y;
  covergroup G;
    a: coverpoint x;
    b: coverpoint y;
    pair: cross a, b {
      function CrossQueueType chosen();
        CrossValType tuple;
        tuple = '{0, 0};
        return '{tuple};
      endfunction
      bins zero = chosen();
    }
  endgroup
  G g = new;
endmodule

// CHECK-NOT: simulation.vpi_typespec.decl {{.*}}"top.G.pair.
// CHECK: simulation.storage.decl {{.*}}hierarchy "top.G.pair.chosen.chosen"
// CHECK-NOT: typedefAliases
// CHECK: simulation.storage.decl {{.*}}hierarchy "top.G.pair.chosen.tuple"
// CHECK-NOT: typedefAliases
// CHECK: simulation.code_unit.decl
