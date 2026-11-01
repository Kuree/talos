// CLAUSE: Nondegenerate sequences evaluate as properties; forbidden degenerate uses are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.12.22/property.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.12.22/admits_empty.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.12.22/overlap.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/16.12.22/nomatch.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: sequence must not admit an empty match
// DIAG: sequence must not admit an empty match
// DIAG: sequence admits only empty matches
// DIAG: antecedent of a nonoverlapping implication must admit at least one match
// CHECK: sequence pass=3 fail=1{{$}}
// CHECK-NEXT: empty antecedent pass=2 fail=2{{$}}

// 16.12.22: rules a, b and c each have a fixture; the legal forms are counted over ticks chosen to tell them apart.
module top;
  bit clk = 0, a = 0, b = 1;
  int p1 = 0, f1 = 0, p2 = 0, f2 = 0;
  // Nondegenerate, and its empty alternative of a[*0:2] is absorbed by ##1.
  assert property (@(posedge clk) a[*0:2] ##1 b) p1++; else f1++;
  // Rule c admits an only-empty antecedent for |=>, which then behaves as b.
  assert property (@(posedge clk) 1'b1[*0] |=> b) p2++; else f2++;
  task tick(bit na, bit nb);
    #1 a = na; b = nb;
    #1 clk = 1;
    #1 clk = 0;
  endtask
  initial begin
    tick(0, 1);
    tick(0, 0);
    tick(1, 0);
    tick(1, 1);
    #1 $display("sequence pass=%0d fail=%0d", p1, f1);
    $display("empty antecedent pass=%0d fail=%0d", p2, f2);
    $finish;
  end
endmodule
