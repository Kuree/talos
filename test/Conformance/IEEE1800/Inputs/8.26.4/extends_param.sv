interface class PutImp;
endclass
interface class Fifo #(type T = PutImp) extends T;
endclass
module top;
  Fifo #() f;
endmodule
