// RUN: talos -O0 --mlir-verify-each %s -o %t.o0 && %t.o0 | FileCheck %s
// RUN: talos -O3 --execution-tier=bytecode --mlir-verify-each %s -o %t.bc && %t.bc | FileCheck %s
// IEEE 1800-2023 13.4.4: delayed NBAs and event triggers schedule background
// work; a zero-time function returns without waiting for the delay to expire.
// CHECK: function delayed NBA passed
module top;
  logic [7:0] q = 0;
  event ready;
  int seen = 0;
  function automatic void issue(input logic [7:0] v);
    q <= #3 v;
    ->> ready;
  endfunction
  function automatic int property_value(); q <= #3 8'h53; return 1; endfunction
  class Box;
    int value = property_value();
  endclass
  initial begin
    Box box;
    issue(8'h31);
    if ($time != 0 || q !== 0) $fatal(1, "function blocked");
    #1;
    if (q !== 0 || seen != 1) $fatal(1, "early publication");
    #3;
    if (q !== 8'h31 || seen != 1) $fatal(1, "background work missing");
    fork begin issue(8'h42); end join_none
    #1;
    if (q !== 8'h31 || seen != 2) $fatal(1, "fork function blocked");
    #3;
    if (q !== 8'h42) $fatal(1, "fork background NBA missing");
    box = new;
    if (box.value != 1) $fatal(1, "property initializer missing");
    #1;
    if (q !== 8'h42) $fatal(1, "property function blocked");
    #3;
    if (q !== 8'h53) $fatal(1, "property background NBA missing");
    $display("function delayed NBA passed"); $finish;
  end
  always @ready seen++;
endmodule
