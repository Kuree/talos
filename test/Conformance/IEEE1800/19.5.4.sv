// CLAUSE: Wildcard bins exclude unknown sampled values
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  logic [1:0] value;
  covergroup G;
    cp: coverpoint value { wildcard bins one = {2'b?1}; }
  endgroup
  G g;
  initial begin
    g = new;
    value = 2'bx1; g.sample();
    if (g.cp.get_inst_coverage() != 0) $fatal(1, "unknown sample");
    value = 1; g.sample();
    if (g.cp.get_inst_coverage() != 100) $fatal(1, "wildcard match");
    $display("PASS");
  end
endmodule
