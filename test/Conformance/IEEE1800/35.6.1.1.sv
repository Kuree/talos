// CLAUSE: Open arrays use the formal's C element type and the actual packed width
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/35.6.1.1/dpi_helpers.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" function int exchange(inout logic [] logic_values[], inout bit [] bit_values[]);
  byte unsigned bits[];
  logic [1:0][2:0] four_state[];
  initial begin
    bits = '{8'h25};
    four_state = '{6'b1x_0z01};
    if (!exchange(four_state, bits)) $fatal(1, "packed open-array copy-in");
    if (four_state[0] !== 6'b000x1x || bits[0] !== 8'h39)
      $fatal(1, "packed open-array copy-out");
    $display("PASS");
  end
endmodule
