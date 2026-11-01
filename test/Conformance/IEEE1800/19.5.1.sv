// CLAUSE: Fixed bins distribute consecutive values together
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int hits, total;
  covergroup G with function sample(bit [1:0] value);
    cp: coverpoint value { bins pair[2] = {[0:3]}; }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample(0); g.sample(1);
    if (g.cp.get_inst_coverage(hits, total) != 50 || hits != 1 || total != 2)
      $fatal(1, "fixed bin grouping");
    $display("PASS");
  end
endmodule
