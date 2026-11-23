// RV32IM workload for RSD TestMain. Link .text at the reset vector (0x1000).
// Each pass streams through 16 KiB of instructions and a 2 KiB RAM window.
// The final checksum is in a0 and the PC goal is 0x1004.
.text
.globl _start
_start:
    j init
goal:
    j goal
init:
    li a0, 1
    li a1, 3
    lui a2, 0x80000
    li a3, 3
pass:
    .set slot, 0
    .rept 32
    li a4, 8
1:
    .rept 16
    addi a0, a0, slot + 1
    sw   a0, slot * 4(a2)
    xor  a1, a1, a0
    lw   t0, slot * 4(a2)
    srli t1, a1, 7
    add  a0, t0, t1
    mul  a1, a1, a3
    xor  a0, a0, a1
    .set slot, slot + 1
    .endr
    addi a4, a4, -1
    bnez a4, 1b
    .endr
    addi a3, a3, -1
    beqz a3, done
    j pass
done:
    j goal
