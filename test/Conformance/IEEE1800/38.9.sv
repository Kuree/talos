// CLAUSE: vpi_get_data returns saved bytes in chunks of any size at restart, zero-filling a read past the end
// XFAIL: *
// The compiler rejects $save and $restart as unsupported system calls; the runtime has no cbStartOfSave or cbStartOfRestart, and vpi_get_data always returns 0.
// RUN: %clang -shared -fPIC %S/Inputs/38.9/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// RUN: %t.exe +restart
// CHECK: state=1 t=1
// CHECK: chunk n=2 ab
// CHECK-NEXT: chunk n=5 cdefg
// CHECK-NEXT: past end n=1 h zero=1
// CHECK-NEXT: state=1 t=1

module top;
timeunit 1ns; timeprecision 1ns;
int state = 0;
initial if ($test$plusargs("restart")) $restart("38.9.sav");
initial begin
  state = $test$plusargs("restart") ? 99 : 1; // only the saved state can print 1 in the restart run
  #1 $save("38.9.sav");
  $display("state=%0d t=%0t", state, $time);
  $finish;
end
endmodule
