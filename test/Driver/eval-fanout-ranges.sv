// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t && %t > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

// A 130-bit range overlaps waits in several words. Two matching posedges
// within an atomic assignment wake the same process once (9.4.2).
module top;
  logic [192:0] data = '0, next_value = '0;
  int phase, edges, changes;
  bit [6:1] edge_times, change_times;
  always @(posedge data[2] or posedge data[8] or posedge data[24] or
           posedge data[63] or posedge data[65] or posedge data[79] or
           posedge data[96] or posedge data[127] or posedge data[161] or
           posedge data[191]) begin
    edges++;
    edge_times[phase] = 1;
  end
  always @(data[129:0]) begin
    changes++;
    change_times[phase] = 1;
  end
  initial begin
    #1 phase = 1; next_value[79] = 1; next_value[161] = 1; data <= next_value;
    #1 phase = 2; next_value = '0; next_value[191] = 1; data <= next_value;
    #1 phase = 3; next_value[79] = 1'bx; data <= next_value;
    #1 phase = 4; next_value[79] = 1'bz; data <= next_value;
    #1 phase = 5; next_value = '0; next_value[2] = 1; data <= next_value;
    #1 phase = 6; next_value[161] = 1; data <= next_value;
    #1 $display("edges %b %0d changes %b %0d",
                edge_times, edges, change_times, changes);
    $finish;
  end
endmodule
// CHECK: edges 110111 5 changes 011111 5
