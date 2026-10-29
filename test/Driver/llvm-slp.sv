// RUN: talos -O1 --two-state -emit-llvm %s | FileCheck %s --check-prefix=SCALAR
// RUN: talos -O2 --two-state -emit-llvm %s | FileCheck %s --check-prefix=VECTOR
// RUN: talos -O3 --two-state -emit-llvm %s | FileCheck %s --check-prefix=VECTOR
// RUN: %target_clang -c %S/Inputs/llvm-slp.c -o %t.input.o
// RUN: talos -O2 --two-state %s %t.input.o -o %t.exe
// RUN: %t.exe | FileCheck %s --check-prefix=OUTPUT

// The frontend unrolls these independent 32-bit lanes. LLVM's library default
// disables SLP, so merely requesting its O2/O3 pipeline used to leave scalar
// loads, xors, and stores here. DPI inputs keep the lane values dynamic; the
// companion checks that vectorization preserves the ordered input calls and
// the per-bit results (IEEE 1800-2023 4.6 and 11.4.8).
// SCALAR-NOT: xor <
// VECTOR: load <{{[248]}} x i32>
// VECTOR: xor <{{[248]}} x i32>
// VECTOR: store <{{[248]}} x i32>
// OUTPUT: 12345678 12345679 1234567a 1234567b 1234567c 1234567d 1234567e 1234567f
module llvm_slp;
  import "DPI-C" function int slp_source(input int index);
  bit [31:0] words [8];
  initial begin
    for (int i = 0; i < 8; i++) words[i] = slp_source(i);
    for (int i = 0; i < 8; i++) words[i] ^= 32'h12345678;
    $display("%h %h %h %h %h %h %h %h", words[0], words[1], words[2],
             words[3], words[4], words[5], words[6], words[7]);
  end
endmodule
