// CLAUSE: Attributes attach to items, statements, operators, calls and connections without changing results
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.12/nested.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.12/value.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: attributes are not allowed here
// DIAG: reference to non-constant variable 'w' is not allowed in a constant expression
// CHECK: case 10{{$}}
// CHECK-NEXT: operator 5{{$}}
// CHECK-NEXT: call 6{{$}}
// CHECK-NEXT: items 4 4{{$}}

// 5.12: the standard gives attributes no simulation effect, so the results must equal the attribute-free ones.
module sub(input int p, output int q);
  assign q = p + 1;
endmodule
module top;
  (* mark = "item" *) int v = 3;
  (* c = "x", c = "y" *) int d = 4;
  int a = 2, b = 3, r, q;
  (* full_case, parallel_case = 1 *)
  function automatic int f(int x);
    return x * 2;
  endfunction
  (* instance_mark *) sub u((* conn *) .p(v), .q(q));
  initial begin
    (* full_case = 1 *)
    (* parallel_case = 1 *)
    case (a)
      2: r = 10;
      default: r = 20;
    endcase
    $display("case %0d", r);
    r = a + (* mode = "cla" *) b;
    $display("operator %0d", r);
    r = f (* inline *) (b);
    $display("call %0d", r);
    (* stmt *) r = d;
    #1 $display("items %0d %0d", r, q);
    $finish;
  end
endmodule
