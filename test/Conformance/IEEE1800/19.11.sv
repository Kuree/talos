// CLAUSE: Group coverage is the weighted mean of its items
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit x, y;
  covergroup G;
    a: coverpoint x { option.weight = 3; }
    b: coverpoint y;
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    x = 1; g.sample();
    if (g.get_inst_coverage() != 87.5) $fatal(1, "weighted mean");
    $display("PASS");
  end
endmodule
