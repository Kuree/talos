// CLAUSE: Crosses define tuple and queue types
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
      function CrossQueueType chosen();
        CrossValType tuple;
        tuple = '{0, 0};
        return '{tuple};
      endfunction
      bins zero = chosen();
    }
  endgroup
  G g;
  initial begin
    g = new;
    g.sample();
    if (g.pair.get_inst_coverage() != 25) $fatal(1, "cross types");
    $display("PASS");
  end
endmodule
