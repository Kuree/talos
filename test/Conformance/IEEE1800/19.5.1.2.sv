// CLAUSE: Array bin values are captured at construction
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  int choices[2] = '{1, 3};
  covergroup G with function sample(int value);
    cp: coverpoint value { bins chosen[] = choices; }
  endgroup
  G g;
  initial begin
    g = new;
    choices = '{2, 2};
    g.sample(1);
    if (g.cp.get_inst_coverage() != 50) $fatal(1, "bin snapshot");
    $display("PASS");
  end
endmodule
