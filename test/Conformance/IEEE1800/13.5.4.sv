// CLAUSE: Arguments bind by name with defaults filling the rest; positional after named is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.4/order.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.4/required.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: ordered arguments are not allowed after named arguments
// DIAG: argument 'b' is missing a value
// CHECK: fun 2 yes{{$}}
// CHECK-NEXT: fun 1 yes{{$}}
// CHECK-NEXT: fun 1 yes{{$}}
// CHECK-NEXT: fun 2 no{{$}}
// CHECK-NEXT: fun 2 yes{{$}}
// CHECK-NEXT: fun 1 no{{$}}
// CHECK-NEXT: fun 2 no{{$}}
// CHECK-NEXT: fun 1 no{{$}}
// CHECK-NEXT: fun 2 yes{{$}}

// 13.5.4: every call form from the clause, with the value each one received.
module top;
  function automatic int fun(int j = 1, string s = "no");
    $display("fun %0d %s", j, s);
    return j;
  endfunction
  initial begin
    void'(fun(.j(2), .s("yes")));
    void'(fun(.s("yes")));
    void'(fun(, "yes"));
    void'(fun(.j(2)));
    void'(fun(.s("yes"), .j(2)));
    void'(fun(.s(), .j()));
    void'(fun(2));
    void'(fun());
    void'(fun(2, .s("yes")));
    $finish;
  end
endmodule
