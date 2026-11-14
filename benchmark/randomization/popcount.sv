// Arbitrary-precision ranks: C(130, 65) exceeds a 64-bit cardinality.
module top;
  parameter int ITERATIONS = 1000;
  parameter bit CHANGING = 0;
  bit [129:0] value;
  int count = 65;
  longint unsigned checksum = 0;

  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      if (CHANGING)
        count = 64 + (i % 3);
      if (!std::randomize(value) with { $countones(value) == count; })
        $fatal(1, "randomization failed");
      if ($countones(value) != count)
        $fatal(1, "invalid sample");
      checksum += value[63:0] ^ value[127:64] ^ longint'(value[129:128]);
    end
    $display("iterations=%0d changing=%0d checksum=%0d", ITERATIONS,
             CHANGING, checksum);
  end
endmodule
