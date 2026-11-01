// CLAUSE: Bin filters run before values are distributed
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  covergroup G with function sample(bit [1:0] value);
    cp: coverpoint value { bins pair[2] = {[0:3]} with (item < 2); }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample(0);
    if (g.cp.get_inst_coverage() != 50) $fatal(1, "filter ordering");
    g.sample(1);
    if (g.cp.get_inst_coverage() != 100) $fatal(1, "filtered bins");
    $display("PASS");
  end
endmodule
