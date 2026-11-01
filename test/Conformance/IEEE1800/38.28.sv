// CLAUSE: vpi_mcd_printf writes C-formatted text to each channel of an mcd, returns the character count, and does not write to an fd
// XFAIL: *
// The runtime has no vpi_mcd_open, vpi_mcd_printf or vpi_mcd_close (undefined symbols at link).
// RUN: %clang -c -fPIC %S/Inputs/38.28/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.28.vpi.out
// RUN: %FileCheck %s --check-prefix=FILE1 --input-file=38.28.mcd.out
// RUN: %FileCheck %s --check-prefix=FILE2 --input-file=38.28.fd.out
// CHECK: count=23
// CHECK-NEXT: to the output channel too
// FILE0: n=7 s=abc x=ff f= 1.50
// FILE0-NEXT: to the output channel too
// FILE1: through a $fopen mcd
// FILE2: from source
// FILE2-NOT: through an fd

module top;
import "DPI-C" context function void probe(input int mcd, input int fd);
int mcd, fd;
initial begin
  mcd = $fopen("38.28.mcd.out");
  fd = $fopen("38.28.fd.out", "w");
  probe(mcd, fd);
  $fdisplay(fd, "from source");
  $fclose(mcd);
  $fclose(fd);
  $finish;
end
endmodule
