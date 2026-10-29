// RUN: talos -O3 --forward-copies=off -G mode=0 %s -o %t.zero.base && %t.zero.base | FileCheck %s && talos -O3 -G mode=0 %s -o %t.zero.native && %t.zero.native | FileCheck %s && talos -O3 --execution-tier=bytecode -G mode=0 %s -o %t.zero.bytecode && %t.zero.bytecode | FileCheck %s
// RUN: talos -O3 --forward-copies=off -G mode=1 %s -o %t.event.base && %t.event.base | FileCheck %s && talos -O3 -G mode=1 %s -o %t.event.native && %t.event.native | FileCheck %s && talos -O3 --execution-tier=bytecode -G mode=1 %s -o %t.event.bytecode && %t.event.bytecode | FileCheck %s
// RUN: talos -O3 --forward-copies=off -G mode=2 %s -o %t.delayed.base && %t.delayed.base | FileCheck %s && talos -O3 -G mode=2 %s -o %t.delayed.native && %t.delayed.native | FileCheck %s && talos -O3 --execution-tier=bytecode -G mode=2 %s -o %t.delayed.bytecode && %t.delayed.bytecode | FileCheck %s
// RUN: talos -O3 --forward-copies=off -G mode=3 %s -o %t.dynamic.base && %t.dynamic.base | FileCheck %s && talos -O3 -G mode=3 %s -o %t.dynamic.native && %t.dynamic.native | FileCheck %s && talos -O3 --execution-tier=bytecode -G mode=3 %s -o %t.dynamic.bytecode && %t.dynamic.bytecode | FileCheck %s
// RUN: talos -O3 --forward-copies=off -G mode=4 %s -o %t.positive.base && %t.positive.base | FileCheck %s --check-prefix=POSITIVE && talos -O3 -G mode=4 %s -o %t.positive.native && %t.positive.native | FileCheck %s --check-prefix=POSITIVE && talos -O3 --execution-tier=bytecode -G mode=4 %s -o %t.positive.bytecode && %t.positive.bytecode | FileCheck %s --check-prefix=POSITIVE

// IEEE 1800-2023 4.4.2.4, 4.9.1, 4.9.4: multiple NBAs can commit in one
// drain even when #0 or an event wait separates their issuing activations.
// Delayed NBAs can also align after positive producer delays. The copies
// filter the source's 1 -> 0 -> 1 transient; their edge waiters must remain.
// Proven positive separation of immediate NBAs is different (mode 4).
module forward_copy_nba_epochs #(parameter int mode = 0);
  logic [3:0] source;
  logic variable_copy;
  wire net_copy = source[0];
  assign variable_copy = source[0];
  int variable_edges = 0, net_edges = 0;
  time dynamic_delay = 2;
  event pause_done, resume;

  always @(posedge variable_copy) variable_edges++;
  always @(posedge net_copy) net_edges++;

  initial begin
    if (mode == 1) begin
      @(pause_done);
      #0;
      -> resume;
    end
  end

  initial begin
    source <= 4'hf;
    #1;
    if (mode == 2 || mode == 3) begin
      if (mode == 2)
        source <= #2 4'he;
      else
        source <= #(dynamic_delay) 4'he;
      #1;
      if (mode == 2)
        source <= #1 4'hf;
      else begin
        dynamic_delay = 1;
        source <= #(dynamic_delay) 4'hf;
      end
      #2;
    end else begin
      source <= 4'he;
      if (mode == 1) begin
        -> pause_done;
        @(resume);
      end else if (mode == 4)
        #1;
      else
        #0;
      source <= 4'hf;
      #1;
    end
    $display("edges=%0d/%0d", variable_edges, net_edges);
    $finish(0);
  end
endmodule

// CHECK: edges=1/1
// POSITIVE: edges=2/2
