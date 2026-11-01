// CLAUSE: Derived abort operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// reject_on(c) P is not(accept_on(c) not P), so not(reject_on(c) P) must equal accept_on(c) not P, and likewise for the
// synchronous pair. Each attempt is a ##1 b ##1 b. c is sampled true at tick 5 (all forms) and pulsed after ticks 0
// and 12 (asynchronous forms only).
// CHECK: RP=0000000000100000 RF=1111021101111111
// CHECK: NP=1111021101111111 NF=0000000000100000
// CHECK: EP=1111021101111111 EF=0000000000100000
// CHECK: SP=0000000000100010 SF=0121021101110111
// CHECK: NSP=0121021101110111 NSF=0000000000100010
// CHECK: ESP=0121021101110111 ESF=0000000000100010

module top;
  bit clk, a, b, c; int t;
  bit [0:15] A = 16'b1000100010001000, B = 16'b0100011001100110;
  bit [0:15] C = 16'b0000010000000000, PULSE = 16'b1000000000001000;
  bit [0:15][3:0] RP, RF, NP, NF, EP, EF, SP, SF, NSP, NSF, ESP, ESF;
  assert property (@(posedge clk) reject_on(c) (a ##1 b ##1 b)) RP[t]++; else RF[t]++;
  assert property (@(posedge clk) not(reject_on(c) (a ##1 b ##1 b))) NP[t]++; else NF[t]++;
  assert property (@(posedge clk) accept_on(c) not(a ##1 b ##1 b)) EP[t]++; else EF[t]++;
  assert property (@(posedge clk) sync_reject_on(c) (a ##1 b ##1 b)) SP[t]++; else SF[t]++;
  assert property (@(posedge clk) not(sync_reject_on(c) (a ##1 b ##1 b))) NSP[t]++; else NSF[t]++;
  assert property (@(posedge clk) sync_accept_on(c) not(a ##1 b ##1 b)) ESP[t]++; else ESF[t]++;
  initial begin
    for (t = 0; t < 16; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1; c = PULSE[t];
      #1 clk = 0; c = 0;
      #1;
    end
    $display("RP=%h RF=%h", RP, RF);
    $display("NP=%h NF=%h", NP, NF);
    $display("EP=%h EF=%h", EP, EF);
    $display("SP=%h SF=%h", SP, SF);
    $display("NSP=%h NSF=%h", NSP, NSF);
    $display("ESP=%h ESF=%h", ESP, ESF);
  end
endmodule
