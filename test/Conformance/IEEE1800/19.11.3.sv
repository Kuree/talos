// CLAUSE: Merged type coverage unions instance bins
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  covergroup G with function sample(bit value);
    type_option.merge_instances = 1;
    coverpoint value;
  endgroup
  G a, b;
  initial begin
    a = new; b = new;
    a.sample(0); b.sample(1);
    if (G::get_coverage() != 100) $fatal(1, "merged coverage");
    $display("PASS");
  end
endmodule
