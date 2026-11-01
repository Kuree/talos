// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos --talos-sim-prepare | FileCheck %s
// RUN: talos -DCALL_RECEIVER -emit-slang %s | not talos-opt --convert-slang-to-talos --talos-sim-prepare -o /dev/null 2>&1 | FileCheck %s --check-prefix=CALL

// IEEE 1800-2023 13.5.3: a default argument is evaluated in the scope containing
// the subroutine declaration each time a call uses it. A virtual interface call
// selects that scope at run time, so the default reads the selected instance's
// member and not the interface type's placeholder.
interface Bus;
  int base = 100;
  function int bump(input int x = base + 7);
    return x;
  endfunction
endinterface

class Handle;
  virtual Bus v;
`ifdef CALL_RECEIVER
  virtual Bus all[2];
  function int pick();
    return 1;
  endfunction
  // CALL: error: a default argument reading interface state requires a virtual interface receiver without calls
  function int get();
    return all[pick()].bump();
  endfunction
`else
  function int get();
    return v.bump();
  endfunction
`endif
endclass

module top;
  Bus bus();
endmodule

// CHECK: callee_name = "bump"
// CHECK: referenced_path = "Handle::v"
// CHECK: talos.sv.expression.binary_op
// CHECK-NEXT: talos.sv.expression.member_access attributes {{{.*}}member_name = "base"{{.*}}referenced_path = "Handle::Bus.base"
// CHECK-NEXT: talos.sv.expression.named_value {{.*}}referenced_path = "Handle::v"
