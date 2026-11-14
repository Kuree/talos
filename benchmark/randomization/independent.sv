// Scale FIELDS to check independent-constraint compilation and simulation.
module top;
  parameter int ITERATIONS = 1000;
  parameter int FIELDS = 64;
  parameter bit CHANGING = 0;
  bit [15:0] values[FIELDS];
  int unsigned limit = 100;
  longint unsigned checksum = 0;

  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      if (CHANGING)
        limit = 100 + (i % 8);
      if (!std::randomize(values) with {
            foreach (values[j]) values[j] < limit;
          })
        $fatal(1, "randomization failed");
      foreach (values[j]) begin
        if (values[j] >= limit)
          $fatal(1, "invalid sample");
        checksum += (j + 1) * longint'(values[j]);
      end
    end
    $display("iterations=%0d fields=%0d changing=%0d checksum=%0d",
             ITERATIONS, FIELDS, CHANGING, checksum);
  end
endmodule
