interface class PutImp;
endclass
class Fifo #(type T = PutImp) implements T;
endclass
module top;
  Fifo #() f;
endmodule
