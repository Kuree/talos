// RUN: not talos -emit-slang -DBAD_AND %s 2>&1 | FileCheck %s --check-prefix=AND
// RUN: not talos -emit-slang -DBAD_CONST %s 2>&1 | FileCheck %s --check-prefix=CONST
// RUN: not talos -emit-slang -DBAD_INTERSECT %s 2>&1 | FileCheck %s --check-prefix=INTERSECT
// RUN: not talos -emit-slang -DBAD_NESTED %s 2>&1 | FileCheck %s --check-prefix=NESTED
// RUN: talos -emit-slang -DLEGAL %s 2>&1 | FileCheck %s --check-prefix=LEGAL

// IEEE 1800-2023 16.12.22 c): the antecedent of |=> shall admit at least one
// match. Each form below can never match; an only-empty antecedent and a
// never-matching sequence outside an antecedent are not rejected by this rule.
module top;
  bit clk, a, b;
`ifdef BAD_AND
  assert property (@(posedge clk) (a and 1'b0) |=> b);
  // AND: error: IEEE 1800-2023 16.12.22: the antecedent of a nonoverlapping implication must admit at least one match
`endif
`ifdef BAD_CONST
  assert property (@(posedge clk) 1'b0 |=> b);
  // CONST: error: IEEE 1800-2023 16.12.22: the antecedent of a nonoverlapping implication must admit at least one match
`endif
`ifdef BAD_INTERSECT
  assert property (@(posedge clk) (a intersect (b ##1 b)) |=> a);
  // INTERSECT: error: IEEE 1800-2023 16.12.22: the antecedent of a nonoverlapping implication must admit at least one match
`endif
`ifdef BAD_NESTED
  assert property (@(posedge clk) a |=> (1'b0 ##1 b) |=> a);
  // NESTED: error: IEEE 1800-2023 16.12.22: the antecedent of a nonoverlapping implication must admit at least one match
`endif
`ifdef LEGAL
  assert property (@(posedge clk) 1'b1[*0] |=> b);
  assert property (@(posedge clk) a[*0:2] |=> b);
  assert property (@(posedge clk) 1'b0);
  // LEGAL: slang.symbol.definition
`endif
endmodule
