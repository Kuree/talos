// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t && %t > %t.out
// RUN: FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

module top;
  bit clk, gate;
  wire copy_clk = clk;
  int sequence_code, pos_hits, neg_hits, computed_hits, conditional_hits;
  always #5 clk = !clk;
  always @(posedge copy_clk) pos_hits++;
  always @(negedge clk) neg_hits++;
  always @(posedge (gate && copy_clk)) computed_hits++;
  initial begin
    #7 gate = 1;
    #14 gate = 0;
  end
  initial begin
    fork
      begin
        @(posedge clk);
        sequence_code = 1;
        @(negedge copy_clk);
        sequence_code = 12;
        #12;
        @(posedge copy_clk);
        sequence_code = 123;
      end
      begin
        @(posedge clk iff gate);
        conditional_hits++;
      end
    join
  end
  initial begin
    #42;
    $display("sequence=%0d pos=%0d neg=%0d computed=%0d conditional=%0d",
             sequence_code, pos_hits, neg_hits, computed_hits, conditional_hits);
    $finish;
  end
endmodule
// CHECK: sequence=123 pos=4 neg=4 computed=2 conditional=1
