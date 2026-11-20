// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t > %t.out 2> %t.diag && FileCheck %s < %t.out && FileCheck %s --check-prefix=FIFO < %t.diag
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.two && %t.two > %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -

// IEEE 1800-2023 9.4.2 and 10.4.2. A write to a subrange can start in one
// source word and wake a different wait in the next. A whole-vector pulse
// leaves the original value in storage while making each matching waiter
// ready once. X to Z is also a change.
module top;
  bit clk;
  logic [512:0] bus = '0;
  int phase, lo, cross_word, hi, whole;
  always #5 clk = !clk;
  always @(bus[7:0]) lo++;
  always @(bus[69:62]) cross_word++;
  always @(bus[129:125]) hi++;
  always @(bus) whole++;
  always @(posedge clk) begin
    case (phase)
      0: bus[89:26] <= 64'h0000_0040_0000_0000;
      1: begin
        bus <= (513'd1 << 512) | (513'd1 << 126) | 513'd4;
        bus <= bus;
      end
      2: bus[66:63] <= 4'bx0z1;
      3: bus[66:63] <= 4'bz0x1;
    endcase
    phase++;
  end
  initial begin
    #6;
    repeat (4) begin
      $display("%0d %0d %0d %0d %0d %b", phase, lo, cross_word, hi, whole, bus[66:63]);
      #10;
    end
    $display("top=%b", bus[512]);
    $finish;
  end
endmodule
// CHECK: 1 0 1 0 1 0010
// CHECK-NEXT: 2 1 2 1 2 0010
// CHECK-NEXT: 3 1 3 1 3 x0z1
// CHECK-NEXT: 4 1 4 1 4 z0x1
// CHECK-NEXT: top=0
// FIFO: talos-nba-fifo mapped_changes={{[1-9][0-9]*}}
