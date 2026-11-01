// CLAUSE: Object RNGs ignore other objects and thread draws
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

class Item;
  rand int value;
endclass
module top;
  Item a, b;
  int first;
  initial begin
    a = new; b = new;
    a.srandom(17); b.srandom(17);
    if (!a.randomize()) $fatal;
    first = a.value;
    void'($urandom);
    if (!a.randomize() || !b.randomize()) $fatal;
    if (b.value != first) $fatal(1, "object stability");
    $display("PASS");
  end
endmodule
