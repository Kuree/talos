// IEEE 1800-2023 38.36.3: cbSignal callbacks run at the next safe point after
// their signal occurs, here the start of the next time slot and ahead of its
// timed callbacks, in signal order and then registration order; a signal that
// occurs twice before then runs its callbacks once, and a callback registered
// during the delivery waits for the next one. A callback ending the
// simulation drops no signal that already arrived, and one arriving after the
// last slot's delivery runs at the end of the simulation. Removing a signal's last
// callback, or shutting VPI down, restores the signal's earlier action.
// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi_signal_callbacks.c -I%resource_dir/include -o %t.so
// RUN: talos -O3 --vpi=full %s %t.so -o %t
// RUN: %t > %t.out 2>&1
// RUN: FileCheck %s --input-file=%t.out

module top;
  import "DPI-C" context function void raise_signals();
  import "DPI-C" context function void raise_again();
  import "DPI-C" context function void raise_last();
  import "DPI-C" context function void raise_to_finish();
  initial begin
    #3 raise_signals();
    $display("same slot t=%0t", $time);
    #1 $display("next slot t=%0t", $time);
    #2 raise_again();
    #1 $display("after t=%0t", $time);
    #1 raise_last();
    #1 $display("done t=%0t", $time);
    raise_to_finish();
    #1 $display("not reached");
  end
endmodule

// CHECK-NOT: {{.}}
// CHECK: first=1
// CHECK-NEXT: second=1
// CHECK-NEXT: kill=0 level=3
// CHECK-NEXT: segv=0
// CHECK-NEXT: zero=0
// CHECK-NEXT: 64=1
// CHECK-NEXT: raised t=3
// CHECK-NEXT: same slot t=3
// CHECK-NEXT: first USR1 t=4
// CHECK-NEXT: late registered=1
// CHECK-NEXT: second USR1 t=4
// CHECK-NEXT: third USR2 t=4
// CHECK-NEXT: info USR2 reason=1 own handler=0
// CHECK-NEXT: removed third=1
// CHECK-NEXT: timer t=4
// CHECK-NEXT: next slot t=4
// CHECK-NEXT: late USR2 t=7
// CHECK-NEXT: removed late=1
// CHECK-NEXT: after t=7
// CHECK-NEXT: own handler=1
// CHECK-NEXT: done t=9
// CHECK-NEXT: first USR1 t=10
// CHECK-NEXT: finish=1
// CHECK-NEXT: second USR1 t=10
// CHECK-NEXT: max other t=10
// CHECK-NEXT: first USR1 t=10
// CHECK-NEXT: finish=1
// CHECK-NEXT: second USR1 t=10
// CHECK-NEXT: exit USR1=own
// CHECK-NOT: {{.}}
