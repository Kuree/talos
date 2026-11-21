// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang %target_pic -I%resource_dir/include -c %t/check.c -o %t/check.o
// RUN: %talos --vpi=full --execution-tier=native %t/design.sv %t/check.o -o %t/native
// RUN: cd %t && ./native | FileCheck %s
// RUN: %talos --vpi=full --execution-tier=bytecode %t/design.sv %t/check.o -o %t/bytecode
// RUN: cd %t && ./bytecode | FileCheck %s
// CHECK: PASS

//--- design.sv
module top;
  import "DPI-C" context function int check_mcd();
  import "DPI-C" context function int close_failed(input int fd);
  import "DPI-C" context function int retry_safe(input int failed, replacement);
  int fd, replacement;
  initial begin
    if (!check_mcd()) $fatal(1, "partial MCD close lost a channel");
    fd = $fopen("/dev/full", "w");
    $fwrite(fd, "queued");
    if (!close_failed(fd)) $fatal(1, "failed FD close retired the descriptor");
    replacement = $fopen("new-fd.out", "w");
    if (!replacement || !retry_safe(fd, replacement))
      $fatal(1, "retry closed the replacement FD");
    $fdisplay(replacement, "still open");
    $fclose(replacement);
    $display("PASS");
  end
endmodule

//--- check.c
#include "sv_vpi_user.h"

int retry_safe(int failed, int replacement) {
  if (failed == replacement)
    return 0;
  PLI_UINT32 remaining = vpi_mcd_close((PLI_UINT32)failed);
  return (remaining == 0 || remaining == (PLI_UINT32)failed) &&
         vpi_mcd_name((PLI_UINT32)replacement) != 0;
}

int close_failed(int fd) {
  PLI_UINT32 descriptor = (PLI_UINT32)fd;
  return (descriptor >> 31) && vpi_mcd_close(descriptor) == descriptor &&
         vpi_chk_error(0) && vpi_mcd_name(descriptor) != 0;
}

int check_mcd(void) {
  PLI_UINT32 full = vpi_mcd_open("/dev/full");
  PLI_UINT32 good = vpi_mcd_open("good.out");
  if (!full || !good || vpi_mcd_printf(full | good, "queued") != 6)
    return 0;
  if (vpi_mcd_close(full | good) != full || !vpi_chk_error(0) ||
      !vpi_mcd_name(full) || vpi_mcd_name(good))
    return 0;
  PLI_UINT32 next = vpi_mcd_open("new-mcd.out");
  return next && retry_safe((int)full, (int)next) &&
         vpi_mcd_printf(next, "still open") == 10 && vpi_mcd_close(next) == 0;
}
