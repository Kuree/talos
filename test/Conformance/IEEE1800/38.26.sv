// CLAUSE: vpi_mcd_name returns the file name of a single mcd or fd from $fopen and NULL for anything else
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.26/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.26.mcd.out
// CHECK: mcd=38.26.mcd.out
// CHECK-NEXT: other=38.26.other.out
// CHECK-NEXT: fd=38.26.fd.out
// CHECK-NEXT: two channels=null
// CHECK-NEXT: unopened=null
// CHECK-NEXT: closed=null
// FILE0: through the named descriptor

module top;
import "DPI-C" context function void names(input int mcd, input int other, input int fd);
import "DPI-C" context function void closed(input int mcd);
int mcd, other, fd;
initial begin
  mcd = $fopen("38.26.mcd.out");
  other = $fopen("38.26.other.out");
  fd = $fopen("38.26.fd.out", "w");
  $fdisplay(mcd, "through the named descriptor");
  names(mcd, other, fd);
  $fclose(mcd);
  closed(mcd);
  $fclose(other);
  $fclose(fd);
  $finish;
end
endmodule
