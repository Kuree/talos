// CLAUSE: SV3.1a canonical open-array element access at fixed and arbitrary rank
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/H.14.2/probe.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  typedef bit [32:0] bits_t;
  typedef logic [32:0] logic_t;

  import "DPI" function int exchange(inout bits_t b1[], b2[][], b3[][][], b4[][][][],
                                     inout logic_t l1[], l2[][], l3[][][], l4[][][][]);

  bits_t b1[2:1], b2[2:1][-2:-1], b3[2:1][-2:-1][7:6], b4[2:1][-2:-1][7:6][4:5];
  logic_t l1[2:1], l2[2:1][-2:-1], l3[2:1][-2:-1][7:6], l4[2:1][-2:-1][7:6][4:5];

  initial begin
    b1[2] = 33'h1_12345670;
    b2[2][-2] = 33'h1_12345671;
    b3[2][-2][6] = 33'h1_12345672;
    b4[2][-2][6][5] = 33'h1_12345673;
    l1[2] = 33'hz_7654x2z0;
    l2[2][-2] = 33'hz_7654x2z1;
    l3[2][-2][6] = 33'hz_7654x2z2;
    l4[2][-2][6][5] = 33'hz_7654x2z3;

    if (!exchange(b1, b2, b3, b4, l1, l2, l3, l4)) $fatal(1, "legacy vector get");
    if (b1[2] != 33'h0_89abcdf0 || b2[2][-2] != 33'h0_89abcdf1 ||
        b3[2][-2][6] != 33'h0_89abcdf2 || b4[2][-2][6][5] != 33'h0_89abcdf3)
      $fatal(1, "legacy bit vector put");
    if (l1[2] !== 33'hx_11xz2200 || l2[2][-2] !== 33'hx_11xz2201 ||
        l3[2][-2][6] !== 33'hx_11xz2202 || l4[2][-2][6][5] !== 33'hx_11xz2203)
      $fatal(1, "legacy logic vector put");
    $display("PASS");
  end
endmodule
