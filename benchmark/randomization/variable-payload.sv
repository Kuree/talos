// Word-count headers, byte overhead and live per-byte bounds. The length is
// solved before the payload, as required by IEEE 1800-2023 18.5.7.1.
class Packet;
  rand int unsigned words;
  rand bit [7:0] payload[];
  bit [7:0] low = 8'h20;
  bit [7:0] high = 8'h7e;
  constraint header { words inside {[0:16]}; }
  constraint length { payload.size() == words * 4 + 4; }
  constraint bytes { foreach (payload[i]) payload[i] inside {[low:high]}; }
endclass

module top;
  parameter int ITERATIONS = 1000;
  parameter bit CHANGING = 0;
  Packet packet = new;
  longint unsigned checksum;
  initial begin
    for (int request = 0; request < ITERATIONS; ++request) begin
      if (CHANGING) begin
        packet.low = 8'h20 + request % 8;
        packet.high = 8'h7e - request % 8;
      end
      if (!packet.randomize()) $fatal(1, "payload generation failed");
      if (packet.words > 16 || packet.payload.size() != packet.words * 4 + 4)
        $fatal(1, "invalid payload size");
      checksum += packet.payload.size();
      foreach (packet.payload[i]) begin
        if (packet.payload[i] < packet.low || packet.payload[i] > packet.high)
          $fatal(1, "invalid payload byte");
        checksum += (i + 1) * longint'(packet.payload[i]);
      end
    end
    $display("iterations=%0d changing=%0d checksum=%0d", ITERATIONS, CHANGING, checksum);
  end
endmodule
