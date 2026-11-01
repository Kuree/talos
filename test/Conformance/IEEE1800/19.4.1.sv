// CLAUSE: A derived covergroup replaces its inherited coverpoint
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --coverage=functional -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

class Base;
  bit value;
  covergroup cg;
    cp: coverpoint value;
  endgroup
  function new(); cg = new; endfunction
endclass
class Derived extends Base;
  covergroup extends cg;
    cp: coverpoint value { bins one = {1}; }
  endgroup
endclass
module top;
  Derived d;
  initial begin
    d = new;
    d.value = 1;
    d.cg.sample();
    if (d.cg.cp.get_inst_coverage() != 100) $fatal(1, "override");
    $display("PASS");
  end
endmodule
