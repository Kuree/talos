module top;
  bit c;
  int out;
  always_ff begin
    @(posedge c) out <= 1;
    @(posedge c) out <= 2;
  end
endmodule
