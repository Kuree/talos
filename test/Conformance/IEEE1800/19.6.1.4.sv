// CLAUSE: A tuple queue selects one cross bin
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit x, y;
  int hits, total;
  covergroup G;
    a: coverpoint x;
    b: coverpoint y;
    pair: cross a, b { bins diagonal = '{'{0, 0}, '{1, 1}}; }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    void'(g.pair.get_inst_coverage(hits, total));
    if (hits != 1 || total != 3) $fatal(1, "tuple queue");
    $display("PASS");
  end
endmodule
