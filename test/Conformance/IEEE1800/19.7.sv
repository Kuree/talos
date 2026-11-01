// CLAUSE: The at_least option sets the required hit count
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit value;
  covergroup G;
    option.at_least = 2;
    cp: coverpoint value { bins zero = {0}; }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    if (g.cp.get_inst_coverage() != 0) $fatal(1, "first hit");
    g.sample();
    if (g.cp.get_inst_coverage() != 100) $fatal(1, "second hit");
    $display("PASS");
  end
endmodule
