// CLAUSE: vpi_mcd_open allocates channel bits, reuses existing $fopen descriptors and returns zero on error
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/38.27/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// RUN: %FileCheck %s --check-prefix=FILE0 --input-file=38.27.a.out
// RUN: %FileCheck %s --check-prefix=FILE1 --input-file=38.27.b.out
// RUN: %FileCheck %s --check-prefix=FILE2 --input-file=38.27.from-vpi.out
// RUN: %FileCheck %s --check-prefix=FILE3 --input-file=38.27.fd.out
// CHECK: single bits=1 distinct=1 reserved=0
// CHECK-NEXT: reopen same=1 $fopen same=1 alias same=1
// CHECK-NEXT: tagged descriptor reused=1 write rejected=1
// CHECK-NEXT: bad path=0
// CHECK-NEXT: reopen when full and recycle=1
// FILE0: before reopening
// FILE0-NEXT: to a
// FILE0-NEXT: to both
// FILE1: to b
// FILE1-NEXT: to both
// FILE2: written from SystemVerilog
// FILE3: before reopening
// FILE3-NEXT: after reopening

module top;
  import "DPI-C" context function int probe(input int mcd, fd);
  import "DPI-C" context function int closed(input int mcd);
  int from_c, fd;
  initial begin
    fd = $fopen("38.27.fd.out", "w+");
    $fdisplay(fd, "before reopening");
    $fflush(fd);
    from_c = probe($fopen("38.27.sv.out"), fd);
    $fdisplay(fd, "after reopening");
    $fclose(fd);
    if (!from_c) $fatal(1, "VPI open failed");
    $fdisplay(from_c, "written from SystemVerilog");
    $fclose(from_c);
    if (!closed(from_c)) $fatal(1, "VPI channel still open");
    $finish;
  end
endmodule
