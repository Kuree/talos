// CLAUSE: Instance and type options are separate structures
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  bit value;
  covergroup G;
    coverpoint value;
  endgroup
  G g;
  initial begin
    g = new;
    g.option.name = "instance";
    G::type_option.comment = "type";
    if (g.option.name != "instance" || G::type_option.comment != "type")
      $fatal(1, "option members");
    $display("PASS");
  end
endmodule
