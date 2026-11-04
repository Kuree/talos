// IEEE 1800-2023 38.15: vpi_get_value reports the object's current value in
// the requested format. The runtime resolves a fixed integral object's value
// source on the first read and then loads its bits directly, from the native
// plan's planes while they are authoritative; later reads of the same handles
// must see every change, VPI writes, forces and releases included, with the
// same formatting.
// REQUIRES: native-elf
// RUN: %target_clang -fPIC -shared -nostdlib %S/Inputs/vpi_get_value_repeated.c -I%resource_dir/include -o %t.so
// RUN: talos -O3 --vpi=full --mlir-timing %s %t.so -o %t 2> %t.timing
// RUN: FileCheck %s --check-prefix=ADMISSION < %t.timing
// RUN: %t > %t.out
// RUN: FileCheck %s --input-file=%t.out

// The clocked lanes give the native island enough cost to be admitted beside
// the runtime-owned testbench, so cnt is read from the plan's own planes.
// ADMISSION: native eligibility: eligible=1 fully_eligible=0 cost_effective=1

module top;
  import "DPI-C" context function void probe(int phase);
  typedef struct packed { logic [1:0] hi; logic [1:0] lo; } pair_t;
  typedef enum logic [1:0] { IDLE, RUN, STOP } state_t;
  logic [7:0] r = 8'b0101_xz10;
  int signed s = -5;
  wire w;
  logic drive_w = 1'bz;
  assign w = drive_w;
  bit [3:0] b = 4'h9;
  logic [63:0] q = 64'h8000_0000_0000_0003;
  pair_t p = '{hi: 2'b10, lo: 2'b01};
  state_t e = RUN;
  byte signed sb = -3;
  time tm = 64'd5;
  tri1 pn;
  logic [7:0] cnt = 0;
  // Wider than 64 bits: never resolved, always read by the general path.
  logic [99:0] wide = 100'h5;
  bit clock;
  int ticks[48];
  always #5 clock = ~clock;
  always @(posedge clock) cnt <= cnt + 1;
  for (genvar i = 0; i < 48; ++i) begin
    always @(posedge clock) ticks[i] <= ticks[i] + 1;
  end
  initial begin
    #2 probe(0);
    r = 8'hc3;
    s = 7;
    drive_w = 1'b1;
    b = 4'h0;
    q = 64'h0;
    p = '{hi: 2'b0x, lo: 2'b11};
    e = STOP;
    sb = 8'sh7f;
    tm = 64'd9;
    wide = {4'h1, 96'h0} | 100'h3;
    #5 probe(1);
    r = 8'bzzzz_zzzz;
    s = 32'h7fff_ffff;
    drive_w = 1'b0;
    wide = 100'bx;
    #10 probe(2);
    $finish;
  end
endmodule

// vpiObjTypeVal resolves to vpiVectorVal (9) for packed objects, vpiIntVal (6)
// for int, vpiTimeVal (11) for time and vpiScalarVal (5) for the scalar nets.
// Each handle's first read at t=2 takes the general path and every later one
// the resolved one; both report the same text (checked against a runtime
// without the resolution). A released variable keeps its forced value until
// its next assignment (10.6.2, 38.34): cnt goes from 0x40 to 0x41.
// CHECK: t=2
// CHECK-NEXT: top.r int=82 bin=0101xz10 oct=1XZ hex=5X dec=x str=52 vec=0000005a/0000000c scalar=0 time=82 strength=0/64/64 objtype=9
// CHECK-NEXT: top.s int=-5 bin=11111111111111111111111111111011 oct=37777777773 hex=fffffffb dec=-5 str=fffffffb vec=fffffffb/00000000 scalar=1 time=4294967291 strength=1/64/64 objtype=6
// CHECK-NEXT: top.w int=0 bin=z oct=z hex=z dec=x str=20 vec=00000000/00000001 scalar=2 time=0 strength=2/1/1 objtype=5
// CHECK-NEXT: top.b int=9 bin=1001 oct=11 hex=9 dec=9 str=09 vec=00000009/00000000 scalar=1 time=9 strength=1/64/64 objtype=9
// CHECK-NEXT: top.q int=3 bin=1000000000000000000000000000000000000000000000000000000000000011 oct=1000000000000000000003 hex=8000000000000003 dec=9223372036854775811 str=8020202020202003 vec=00000003/00000000 scalar=1 time=3 strength=1/64/64 objtype=9
// CHECK-NEXT: top.p int=9 bin=1001 oct=11 hex=9 dec=9 str=09 vec=00000009/00000000 scalar=1 time=9 strength=1/64/64 objtype=9
// CHECK-NEXT: top.e int=1 bin=01 oct=1 hex=1 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/64/64 objtype=9
// CHECK-NEXT: top.sb int=-3 bin=11111101 oct=375 hex=fd dec=-3 str=fd vec=000000fd/00000000 scalar=1 time=253 strength=1/64/64 objtype=6
// CHECK-NEXT: top.tm int=5 bin=0000000000000000000000000000000000000000000000000000000000000101 oct=0000000000000000000005 hex=0000000000000005 dec=5 str=2020202020202005 vec=00000005/00000000 scalar=1 time=5 strength=1/64/64 objtype=11
// CHECK-NEXT: top.pn int=1 bin=1 oct=1 hex=1 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/32/32 objtype=5
// CHECK-NEXT: top.cnt int=0 bin=00000000 oct=000 hex=00 dec=0 str=20 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=9
// CHECK-NEXT: top.wide int=5 bin=0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101 oct=0000000000000000000000000000000005 hex=0000000000000000000000005 dec=5 str=20202020202020202020202005 vec=00000005/00000000 scalar=1 time=5 strength=1/64/64 objtype=9
// CHECK-NEXT: t=7
// CHECK-NEXT: top.r int=195 bin=11000011 oct=303 hex=c3 dec=195 str=c3 vec=000000c3/00000000 scalar=1 time=195 strength=1/64/64 objtype=9
// CHECK-NEXT: top.s int=7 bin=00000000000000000000000000000111 oct=00000000007 hex=00000007 dec=7 str=20202007 vec=00000007/00000000 scalar=1 time=7 strength=1/64/64 objtype=6
// CHECK-NEXT: top.w int=1 bin=1 oct=1 hex=1 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/64/64 objtype=5
// CHECK-NEXT: top.b int=0 bin=0000 oct=00 hex=0 dec=0 str=20 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=9
// CHECK-NEXT: top.q int=0 bin=0000000000000000000000000000000000000000000000000000000000000000 oct=0000000000000000000000 hex=0000000000000000 dec=0 str=2020202020202020 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=9
// CHECK-NEXT: top.p int=3 bin=0x11 oct=0X hex=X dec=x str=03 vec=00000007/00000004 scalar=1 time=3 strength=1/64/64 objtype=9
// CHECK-NEXT: top.e int=2 bin=10 oct=2 hex=2 dec=2 str=02 vec=00000002/00000000 scalar=0 time=2 strength=0/64/64 objtype=9
// CHECK-NEXT: top.sb int=127 bin=01111111 oct=177 hex=7f dec=127 str=7f vec=0000007f/00000000 scalar=1 time=127 strength=1/64/64 objtype=6
// CHECK-NEXT: top.tm int=9 bin=0000000000000000000000000000000000000000000000000000000000001001 oct=0000000000000000000011 hex=0000000000000009 dec=9 str=2020202020202009 vec=00000009/00000000 scalar=1 time=9 strength=1/64/64 objtype=11
// CHECK-NEXT: top.pn int=1 bin=1 oct=1 hex=1 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/32/32 objtype=5
// CHECK-NEXT: top.cnt int=1 bin=00000001 oct=001 hex=01 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/64/64 objtype=9
// CHECK-NEXT: top.wide int=3 bin=0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011 oct=0100000000000000000000000000000003 hex=1000000000000000000000003 dec=79228162514264337593543950339 str=01202020202020202020202003 vec=00000003/00000000 scalar=1 time=3 strength=1/64/64 objtype=9
// CHECK-NEXT: deposit top.r int=17 bin=00010001 oct=021 hex=11 dec=17 str=11 vec=00000011/00000000 scalar=1 time=17 strength=1/64/64 objtype=9
// CHECK-NEXT: force top.cnt int=64 bin=01000000 oct=100 hex=40 dec=64 str=40 vec=00000040/00000000 scalar=0 time=64 strength=0/64/64 objtype=9
// CHECK-NEXT: release top.cnt int=64 bin=01000000 oct=100 hex=40 dec=64 str=40 vec=00000040/00000000 scalar=0 time=64 strength=0/64/64 objtype=9
// CHECK-NEXT: t=17
// CHECK-NEXT: top.r int=0 bin=zzzzzzzz oct=zzz hex=zz dec=x str=20 vec=00000000/000000ff scalar=2 time=0 strength=2/64/64 objtype=9
// CHECK-NEXT: top.s int=2147483647 bin=01111111111111111111111111111111 oct=17777777777 hex=7fffffff dec=2147483647 str=7fffffff vec=7fffffff/00000000 scalar=1 time=2147483647 strength=1/64/64 objtype=6
// CHECK-NEXT: top.w int=0 bin=0 oct=0 hex=0 dec=0 str=20 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=5
// CHECK-NEXT: top.b int=0 bin=0000 oct=00 hex=0 dec=0 str=20 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=9
// CHECK-NEXT: top.q int=0 bin=0000000000000000000000000000000000000000000000000000000000000000 oct=0000000000000000000000 hex=0000000000000000 dec=0 str=2020202020202020 vec=00000000/00000000 scalar=0 time=0 strength=0/64/64 objtype=9
// CHECK-NEXT: top.p int=3 bin=0x11 oct=0X hex=X dec=x str=03 vec=00000007/00000004 scalar=1 time=3 strength=1/64/64 objtype=9
// CHECK-NEXT: top.e int=2 bin=10 oct=2 hex=2 dec=2 str=02 vec=00000002/00000000 scalar=0 time=2 strength=0/64/64 objtype=9
// CHECK-NEXT: top.sb int=127 bin=01111111 oct=177 hex=7f dec=127 str=7f vec=0000007f/00000000 scalar=1 time=127 strength=1/64/64 objtype=6
// CHECK-NEXT: top.tm int=9 bin=0000000000000000000000000000000000000000000000000000000000001001 oct=0000000000000000000011 hex=0000000000000009 dec=9 str=2020202020202009 vec=00000009/00000000 scalar=1 time=9 strength=1/64/64 objtype=11
// CHECK-NEXT: top.pn int=1 bin=1 oct=1 hex=1 dec=1 str=01 vec=00000001/00000000 scalar=1 time=1 strength=1/32/32 objtype=5
// CHECK-NEXT: top.cnt int=65 bin=01000001 oct=101 hex=41 dec=65 str=41 vec=00000041/00000000 scalar=1 time=65 strength=1/64/64 objtype=9
// CHECK-NEXT: top.wide int=0 bin=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx oct=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx hex=xxxxxxxxxxxxxxxxxxxxxxxxx dec=x str=20202020202020202020202020 vec=ffffffff/ffffffff scalar=3 time=0 strength=3/64/64 objtype=9
