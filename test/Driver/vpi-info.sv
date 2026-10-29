// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi_info.c -I%resource_dir/include -I%obj_root/include -o %t.so
// RUN: %talos -O0 --vpi=full %s %t.so -o %t.native
// RUN: %t.native | FileCheck %s
// RUN: %talos -O3 -flto --vpi=full %s %t.so -o %t.lto
// RUN: %t.lto | FileCheck %s

module top;
  initial $finish;
endmodule

// CHECK: VPI simulator info matches VERSION: talos
