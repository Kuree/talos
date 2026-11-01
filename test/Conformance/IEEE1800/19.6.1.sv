// CLAUSE: A user cross bin groups several products
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit x, y;
  covergroup G;
    a: coverpoint x;
    b: coverpoint y;
    pair: cross a, b { bins all_pairs = binsof(a); }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    if (g.pair.get_inst_coverage() != 100) $fatal(1, "cross bin");
    $display("PASS");
  end
endmodule
