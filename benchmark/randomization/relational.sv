// Repeated exact sampling with live bounds and a correlated pair of fields.
// Build with -GITERATIONS=N; -GCHANGING=1 changes the capture on each draw.
module top;
  parameter int ITERATIONS = 10000;
  parameter bit CHANGING = 0;
  bit [15:0] x, y;
  int unsigned limit = 100;
  longint unsigned checksum = 0;

  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      if (CHANGING)
        limit = 100 + (i % 8);
      if (!std::randomize(x, y) with {
            x < limit;
            y < limit;
            int'(x) + int'(y) < limit;
            x[1:0] == 0;
          })
        $fatal(1, "randomization failed");
      if (x >= limit || y >= limit || int'(x) + int'(y) >= limit ||
          x[1:0] != 0)
        $fatal(1, "invalid sample");
      checksum += x + 65537 * longint'(y);
    end
    $display("iterations=%0d changing=%0d checksum=%0d", ITERATIONS,
             CHANGING, checksum);
  end
endmodule
