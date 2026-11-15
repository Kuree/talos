// Exercise repeated pure calls across accepted function-argument stages.
// The recurrence keeps the body active after optimization; the narrow random
// domains make solver work small enough to expose repeated body execution.
module top #(
  parameter int ITERATIONS = 10000,
  parameter bit CHANGING = 0
);
  class Chain;
    rand bit a, b, c, d, e, f;
    bit state_bias;

    function automatic bit fold(input bit value);
      bit [31:0] state;
      state = 32'hb315a527 ^ value;
      for (int i = 0; i < 8192; ++i)
        state = (state >> 1) ^ ((state & 1) ? 32'hd0000001 : 0);
      return (state & 1) ^ state_bias;
    endfunction

    constraint chain {
      b == fold(a);
      c == fold(b);
      d == fold(c);
      e == fold(d);
      f == fold(e);
    }
  endclass

  Chain object = new;
  longint unsigned checksum;
  int accepted;
  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      object.state_bias = CHANGING ? (i & 1) : 0;
      accepted += object.randomize();
      checksum += {object.a, object.b, object.c, object.d, object.e, object.f};
    end
    $display("iterations=%0d changing=%0d accepted=%0d checksum=%0d",
             ITERATIONS, CHANGING, accepted, checksum);
  end
endmodule
