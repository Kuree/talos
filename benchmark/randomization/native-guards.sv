// Profile native function captures under sixty-four shared state guards.
// The default and changing cases retain exact seeded replay across compilers.

`define GUARD4(first) if (gates[first]) if (gates[(first)+1]) if (gates[(first)+2]) if (gates[(first)+3])

class GuardedPacket;
  rand bit argument;
  rand bit [31:0] result;
  bit [63:0] gates;

  function automatic bit leaf(input bit value);
    return value;
  endfunction

  // A closed call graph keeps native capture opaque without a long body
  // dominating the runtime measurement.
  function automatic bit identity(input bit value);
    return leaf(value);
  endfunction

  constraint c {
    `GUARD4(0)
    `GUARD4(4)
    `GUARD4(8)
    `GUARD4(12)
    `GUARD4(16)
    `GUARD4(20)
    `GUARD4(24)
    `GUARD4(28)
    `GUARD4(32)
    `GUARD4(36)
    `GUARD4(40)
    `GUARD4(44)
    `GUARD4(48)
    `GUARD4(52)
    `GUARD4(56)
    `GUARD4(60)
    foreach (result[i]) result[i] == identity(argument);
  }
endclass

module top;
  parameter int ITERATIONS = 10000;
  parameter bit CHANGING = 0;
  GuardedPacket packet = new;
  longint unsigned checksum;
  int accepted;

  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      packet.gates = '1;
      if (CHANGING && (i & 1)) packet.gates[63] = 0;
      if (!packet.randomize()) $fatal(1, "guard benchmark randomize failed");
      if ((&packet.gates) && packet.result != {32{packet.argument}})
        $fatal(1, "guard benchmark result mismatch");
      ++accepted;
      checksum += longint'(packet.result) + longint'(packet.argument);
    end
    $display("iterations=%0d changing=%0d accepted=%0d checksum=%0d",
             ITERATIONS, CHANGING, accepted, checksum);
  end
endmodule

`undef GUARD4
