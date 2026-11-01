// CLAUSE: vpi_put_data stores bytes for an id during a save, returns the count, and the bytes come back in order at restart
// XFAIL: *
// The compiler rejects $save and $restart as unsupported system calls; the runtime has no vpi_put_data (undefined symbol at link) or save/restart callbacks.
// RUN: %clang -shared -fPIC %S/Inputs/38.31/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// RUN: %t.exe +restart
// CHECK: put a=3 b=4 c=2 zero=0
// CHECK-DAG: id one n=7 abcdefg
// CHECK-DAG: id two n=2 xy

module top;
initial if ($test$plusargs("restart")) $restart("38.31.sav");
initial begin
  #1 $save("38.31.sav");
  $finish;
end
endmodule
