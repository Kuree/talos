// CLAUSE: Coverpoint coverage counts covered and total bins
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit value;
  int hits, total;
  covergroup G;
    cp: coverpoint value;
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    if (g.cp.get_inst_coverage(hits, total) != 50 || hits != 1 || total != 2)
      $fatal(1, "bin fraction");
    $display("PASS");
  end
endmodule
