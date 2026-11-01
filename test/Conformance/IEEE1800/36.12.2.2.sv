// CLAUSE: The host simulator selects the default compatibility mode for applications without a symbol
// XFAIL: *
// The compiler has no way to set a default VPI compatibility mode; the probe uses the obvious option --vpi-compatibility=1364v2001.
// RUN: %clang -c -fPIC %S/Inputs/36.12.2.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier --vpi-compatibility=1364v2001 %s %t.helper0.o -o %t.legacy.exe
// RUN: %t.legacy.exe
// CHECK: default regs=1 others=1
// CHECK: default regs=0 others=1
// 36.12.2.2: "A means to set the default VPI compatibility mode shall be made available". The application has no symbol.

module top;
  reg r;
  integer i;
  import "DPI-C" context function void probe();
  initial begin
    probe();
    $finish;
  end
endmodule
