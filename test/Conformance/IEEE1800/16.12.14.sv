// CLAUSE: sync accept
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Each attempt is a ##1 b ##1 b. c is sampled true at tick 5, which every form sees. It is also pulsed between ticks
// after ticks 0 and 12, which only the asynchronous forms see; those results land on the index of the tick before.
// The last assertion is the clause's example shape: stop aborts a pending consequent, of the attempts at ticks 0, 4 and 12,
// and the attempt at tick 5 has a false antecedent, so it only passes vacuously.
// CHECK: AP=1000020000101000 AF=0111001101110111
// CHECK: RP=0000000000100000 RF=1111021101111111
// CHECK: SAP=0000020000100010 SAF=0121001101110111
// CHECK: SRP=0000000000100010 SRF=0121021101110111
// CHECK: IF=1000010000001000

module top;
  bit clk, a, b, c; int t;
  bit [0:15] A = 16'b1000100010001000, B = 16'b0100011001100110;
  bit [0:15] C = 16'b0000010000000000, PULSE = 16'b1000000000001000;
  bit [0:15][3:0] AP, AF, RP, RF, SAP, SAF, SRP, SRF, IF;
  assert property (@(posedge clk) accept_on(c) (a ##1 b ##1 b)) AP[t]++; else AF[t]++;
  assert property (@(posedge clk) reject_on(c) (a ##1 b ##1 b)) RP[t]++; else RF[t]++;
  assert property (@(posedge clk) sync_accept_on(c) (a ##1 b ##1 b)) SAP[t]++; else SAF[t]++;
  assert property (@(posedge clk) sync_reject_on(c) (a ##1 b ##1 b)) SRP[t]++; else SRF[t]++;
  assert property (@(posedge clk) a |-> reject_on(c) (##1 b ##1 b)) else IF[t]++;
  initial begin
    for (t = 0; t < 16; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1; c = PULSE[t];
      #1 clk = 0; c = 0;
      #1;
    end
    $display("AP=%h AF=%h", AP, AF);
    $display("RP=%h RF=%h", RP, RF);
    $display("SAP=%h SAF=%h", SAP, SAF);
    $display("SRP=%h SRF=%h", SRP, SRF);
    $display("IF=%h", IF);
  end
endmodule
