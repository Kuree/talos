// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos \
// RUN:   '--lower-talos-to-sim=vpi=full opt-level=0' | FileCheck %s

// IEEE 1800-2023 20.10 defines $fatal, $error, $warning and $info as severity
// system tasks. The frontend types them as functions, but their VPI call
// objects are system task calls (vpiSysTaskCall, 57) like $display's, while a
// system function such as $time stays a system function call
// (vpiSysFuncCall, 56) (37.42). A function body may call them too.
module top;
  time t;
  function automatic void check(int value);
    if (value < 0) $error("negative");
  endfunction
  initial begin
    check(1);
    $display("x");
    if (0) $fatal(1, "f");
    $error("e");
    $warning("w");
    $info("i");
    t = $time;
  end
endmodule

// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$error"
// CHECK: simulation.vpi_call.decl {{.*}} name "check"
// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$display"
// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$fatal"
// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$error"
// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$warning"
// CHECK: simulation.vpi_call.decl {{.*}} type 57 name "$info"
// CHECK: simulation.vpi_call.decl {{.*}} type 56 name "$time"
