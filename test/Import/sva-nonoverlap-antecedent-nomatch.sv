// RUN: not talos -emit-slang -DBAD_NONOVERLAP %s 2>&1 | FileCheck %s --check-prefix=NONOVERLAP
// RUN: not talos -emit-slang -DBAD_OVERLAP %s 2>&1 | FileCheck %s --check-prefix=OVERLAP
// RUN: not talos -emit-slang -DBAD_SIGNALS %s 2>&1 | FileCheck %s --check-prefix=NONOVERLAP
// RUN: not talos -emit-slang -DBAD_NESTED %s 2>&1 | FileCheck %s --check-prefix=NONOVERLAP
// RUN: not talos -emit-slang -DBAD_EMPTY_CONCAT %s 2>&1 | FileCheck %s --check-prefix=NONOVERLAP
// RUN: talos -emit-slang -DLEGAL %s 2>&1 | FileCheck %s --check-prefix=LEGAL

// IEEE 1800-2023 16.12.22 b), c): the antecedent of |-> shall be nondegenerate
// and the antecedent of |=> shall admit at least one match. F.5 defines T |= b
// for any Boolean expression b, so F.5.2 finds a match for an always-false
// Boolean. Only a sequence that no word over the alphabet satisfies is rejected.
module top;
  parameter bit ENABLE = 0;
  bit clk, a, b;
`ifdef BAD_NONOVERLAP
  // The example of a sequence that can never be matched in 16.12.22.
  assert property (@(posedge clk) ((1'b1) intersect (1'b1 ##1 1'b1)) |=> b);
`endif
`ifdef BAD_OVERLAP
  assert property (@(posedge clk) ((1'b1) intersect (1'b1 ##1 1'b1)) |-> b);
`endif
`ifdef BAD_SIGNALS
  assert property (@(posedge clk) (a intersect (b ##1 b)) |=> a);
`endif
`ifdef BAD_NESTED
  assert property (@(posedge clk) a |=> (a intersect (b ##1 b)) |=> a);
`endif
`ifdef BAD_EMPTY_CONCAT
  // F.5.2: the operands of ##0 share a letter, which an empty match lacks.
  assert property (@(posedge clk) (1'b1[*0] ##0 a) |=> b);
`endif
`ifdef LEGAL
  // Rule c admits an only-empty antecedent.
  assert property (@(posedge clk) 1'b1[*0] |=> b);
  assert property (@(posedge clk) a[*0:2] |=> b);
  // Always-false Booleans admit a match through the letter T.
  assert property (@(posedge clk) 1'b0 |=> b);
  assert property (@(posedge clk) 1'b0 |-> b);
  assert property (@(posedge clk) (a and 1'b0) |=> b);
  assert property (@(posedge clk) (1'b0 ##1 b) |=> a);
  assert property (@(posedge clk) (ENABLE && a) |=> b);
  assert property (@(posedge clk) (ENABLE && a) |-> b);
`endif
endmodule

// NONOVERLAP: error: IEEE 1800-2023 16.12.22: the antecedent of a nonoverlapping implication must admit at least one match
// OVERLAP: error: IEEE 1800-2023 16.12.22: the antecedent of an overlapping implication must be nondegenerate
// LEGAL-NOT: error:
// LEGAL: slang.symbol.definition
// LEGAL-NOT: error:
