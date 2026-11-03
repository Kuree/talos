// IEEE 1800-2023 38.36.3: cbStartOfReset and cbEndOfReset bracket a $reset
// (D.8), whether the design or vpi_control(vpiReset) (38.4) asks for it; the
// latter runs once the calling routine returns. $stop, vpi_control(vpiStop)
// and a reset with a zero stop_value enter and leave the interactive mode,
// and $scope (D.11) or vpi_control(vpiSetInteractiveScope) changes the
// interactive scope ($showscopes lists it, D.12), with obj the new scope.
// Only the last two runs reach their final procedures; from one, stopping
// and resetting happen at once.
// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi_feature_callbacks.c -I%resource_dir/include -o %t.so
// RUN: talos -O3 --vpi=full %s %t.so -o %t
// RUN: %t > %t.out 2>&1
// RUN: FileCheck %s --input-file=%t.out

module child;
  task kt;
  endtask
endmodule

module top;
  import "DPI-C" context function void dpi_reset();
  import "DPI-C" context function void dpi_stop();
  import "DPI-C" context function void dpi_fail();
  import "DPI-C" context function void dpi_check();
  import "DPI-C" context function void dpi_final();
  int count;
  child u();
  initial begin : blk
    count = $reset_count;
    $display("run count=%0d value=%0d t=%0t", count, $reset_value, $time);
    #5;
    if (count == 0) begin
      $showscopes;
      dpi_fail();
      // vpi_handle_by_name cannot find a block inside a procedure, so obj is
      // NULL; the runtime's failed lookup is not the application's error.
      $scope(top.blk);
      dpi_check();
    end
    if (count == 1) begin
      $scope(top.u);
      $reset(0, 7);
    end
    if (count == 2) begin
      dpi_reset();
      $display("not reached");
    end
    if (count == 3) begin
      dpi_stop();
      $display("not reached");
    end
    if (count == 0)
      #10 $display("not reached");
  end
  final begin
    $display("final count=%0d", count);
    if (count == 3)
      dpi_final();
  end
endmodule

// CHECK-NOT: {{.}}
// CHECK: run count=0 value=0 t=0
// CHECK-NEXT: timer count=0
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: null scope=0
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: variable scope=0
// CHECK-NEXT: cbInteractiveScopeChange t=2 obj=top.u
// CHECK-NEXT: nested scope=1
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: scope=1 level=0
// CHECK-NEXT: kt
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: cbInteractiveScopeChange t=5 obj=null
// CHECK-NEXT: kept level=3
// CHECK-NEXT: reset=1
// CHECK-NEXT: timer returns
// CHECK-NEXT: cbStartOfReset t=7
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: nested reset=0
// The reset ends before any procedure of the next run starts.
// CHECK-NEXT: cbEndOfReset t=0
// CHECK-NEXT: cbEnterInteractive t=0
// CHECK-NEXT: cbExitInteractive t=0
// CHECK-NEXT: run count=1 value=5 t=0
// CHECK-NEXT: timer count=1
// CHECK-NEXT: cbInteractiveScopeChange t=5 obj=top.u
// CHECK-NEXT: nested scope=1
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: cbStartOfReset t=5
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: nested reset=0
// CHECK-NEXT: cbEndOfReset t=0
// CHECK-NEXT: cbEnterInteractive t=0
// CHECK-NEXT: cbExitInteractive t=0
// CHECK-NEXT: run count=2 value=7 t=0
// CHECK-NEXT: timer count=2
// CHECK-NEXT: dpi reset=1
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: dpi reset returns
// CHECK-NEXT: cbStartOfReset t=5
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: nested reset=0
// CHECK-NEXT: cbEndOfReset t=0
// CHECK-NEXT: run count=3 value=9 t=0
// CHECK-NEXT: timer count=3
// CHECK-NEXT: dpi stop=1
// CHECK-NEXT: cbEnterInteractive t=5
// CHECK-NEXT: nested stop=1
// CHECK-NEXT: cbExitInteractive t=5
// CHECK-NEXT: final count=3
// CHECK-NEXT: cbEnterInteractive t=5
// CHECK-NEXT: nested stop=1
// CHECK-NEXT: cbExitInteractive t=5
// CHECK-NEXT: final stop=1
// CHECK-NEXT: cbStartOfReset t=5
// CHECK-NEXT: cbPLIError
// CHECK-NEXT: nested reset=0
// CHECK-NEXT: cbEndOfReset t=0
// CHECK-NEXT: run count=4 value=11 t=0
// CHECK-NEXT: timer count=4
// CHECK-NEXT: final count=4
// CHECK-NOT: {{.}}
