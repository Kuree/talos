// Profile exact model counting for mutable binary64 equality. Each equality
// joins two 2100-bit numeric coordinates, with many equivalent encodings of
// the same IEEE value. CHANGING exercises live capture invalidation as well.
// Use run.py --case real-equality --iterations 10 for a short profiling run.
class RealPacket;
  rand real a[2];
  rand realtime b[2];
  real target = 0.5;

  constraint c {
    a == b;
    foreach (a[i]) a[i] == target;
  }
endclass

module top;
  parameter int ITERATIONS = 10000;
  parameter bit CHANGING = 0;
  RealPacket packet = new;
  longint unsigned checksum;
  int accepted;

  initial begin
    for (int i = 0; i < ITERATIONS; ++i) begin
      packet.target = CHANGING && (i & 1) ? 1.25 : 0.5;
      if (!packet.randomize()) $fatal(1, "real equality randomize failed");
      foreach (packet.a[j]) begin
        if (packet.a[j] != packet.target || packet.b[j] != packet.target)
          $fatal(1, "real equality result mismatch");
        checksum += $realtobits(packet.a[j]) + $realtobits(packet.b[j]);
      end
      ++accepted;
    end
    $display("iterations=%0d changing=%0d accepted=%0d checksum=%0d state=%s",
             ITERATIONS, CHANGING, accepted, checksum, packet.get_randstate());
  end
endmodule
