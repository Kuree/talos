// RUN: talos -O3 --vpi=off %s -o %t && %t | FileCheck %s
// RUN: talos -O3 --two-state --vpi=off %s -o %t.two && %t.two | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.bc && %t.bc | FileCheck %s

module top;
  string fmt, result, ref_result;
  logic [11:0] mixed;
  function automatic string render(logic [11:0] x, string s, int n);
    return $sformatf("%%[%4H][%-4s][%0d][%0s][%b]", x, s, n, 24'h410042, x[3:0]);
  endfunction
  initial begin
    fmt = "%%[%4H][%-4s][%0d][%0s][%b]";
    result = render(12'hf1a, "s", -7);
    if (result != "%[0f1a][s   ][-7][A B][1010]")
      $fatal(1, "known fields [%s]", result);
    mixed = 12'b001xxx101x01;
    result = render(mixed, "longer than the field width", -2147483648);
    ref_result = $sformatf(fmt, mixed, "longer than the field width",
                           -2147483648, 24'h410042, mixed[3:0]);
    if (result != ref_result)
      $fatal(1, "literal [%s] dynamic [%s]", result, ref_result);
    if ($isunknown(mixed) && $sformatf("%h %o", mixed, mixed) != "XXX 1x5X")
      $fatal(1, "four-state field digits");
    $display("PASS");
    $finish;
  end
endmodule
// CHECK: PASS
