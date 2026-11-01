// CLAUSE: tagged union selects its member by tag
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.3.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: forbids dynamic and chandle types in an untagged union
// CHECK: number 7
// CHECK: text seven

// 7.3.2: the tag records which member is current, and dynamic types may be used
// in a tagged union but not an untagged one.
module top;
  typedef union tagged { int number; string text; } T;
  function automatic void show(T t);
    case (t) matches
      tagged number .n: $display("number %0d", n);
      tagged text .s: $display("text %s", s);
    endcase
  endfunction
  initial begin
    show(tagged number 7);
    show(tagged text "seven");
    $finish;
  end
endmodule
