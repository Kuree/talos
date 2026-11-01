// CLAUSE: Cross-bin union retains the unselected product
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit x, y;
  covergroup G;
    a: coverpoint x;
    b: coverpoint y;
    pair: cross a, b {
      bins zero = binsof(a) intersect {0} || binsof(b) intersect {0};
    }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    if (g.pair.get_inst_coverage() != 50) $fatal(1, "cross union");
    $display("PASS");
  end
endmodule
