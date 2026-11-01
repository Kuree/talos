// CLAUSE: The strobe type option samples after NBA updates
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit clk, value;
  covergroup G @(posedge clk);
    type_option.strobe = 1;
    cp: coverpoint value { bins one = {1}; }
  endgroup
  G g;
  initial begin
    g = new;
    #1; clk = 1; value <= 1;
    #1;
    if (g.cp.get_inst_coverage() != 100) $fatal(1, "strobe sample");
    $display("PASS");
  end
endmodule
