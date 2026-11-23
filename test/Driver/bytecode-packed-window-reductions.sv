// RUN: talos -O0 --execution-tier=bytecode --top=top %s -o %t && %t +low=60 | FileCheck %s
// CHECK: packed checks passed
module top;
  logic [139:0] data;
  logic signed [31:0] low;
  logic [7:0] v;
  initial begin
    if (!$value$plusargs("low=%d", low)) $fatal;
    data = '0;
    data[67:60] = 8'b10zx0101;
    if (data[low +: 8] !== 8'b10zx0101) $fatal;
    data[139:136] = 4'b1010;
    low += 76;
    if (data[low +: 8] !== 8'bxxxx1010) $fatal;
    data[3:0] = 4'b1101;
    low = -4;
    if (data[low +: 8] !== 8'b1101xxxx) $fatal;
    low = 'x;
    if (data[low +: 8] !== 8'hxx) $fatal;
    for (int i = 0; i < 256; i++) begin
      v = i;
      if ((&v) !== (i == 255) || (|v) !== (i != 0) ||
          (^v) !== ($countones(v) % 2 != 0)) $fatal;
    end
    v = data[67:60];
    if ((&v) !== 1'b0 || (~&v) !== 1'b1 || (|v) !== 1'b1 ||
        (~|v) !== 1'b0 || (^v) !== 1'bx || (~^v) !== 1'bx) $fatal;
    v = 8'b111z1111;
    if ((&v) !== 1'bx || (~&v) !== 1'bx) $fatal;
    v = 8'b000x0000;
    if ((|v) !== 1'bx || (!v) !== 1'bx) $fatal;
    $display("packed checks passed");
  end
endmodule
