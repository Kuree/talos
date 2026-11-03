// RUN: talos -O3 --native-scheduler=eval --mlir-timing %s -o %t.eval 2> %t.timing
// RUN: FileCheck %s --check-prefix=PLAN < %t.timing
// RUN: talos -O0 --native-scheduler=generic %s -o %t.generic
// RUN: %t.eval > %t.eval.out
// RUN: %t.generic > %t.generic.out
// RUN: diff -u %t.generic.out %t.eval.out
// RUN: FileCheck %s < %t.eval.out

// Process control (IEEE 1800-2023 9.7) keeps only the controller and the
// processes a handle can name runtime-owned: process::self() callers, also
// through a virtual method, and their fork children. The flop and
// combinational owners of the DUT stay in the generated plan (two-tier P1e).
class Base;
  virtual function process grab();
    return null;
  endfunction
endclass

class Grabber extends Base;
  virtual function process grab();
    return process::self();
  endfunction
endclass

module native_process_control_owners;
  logic clk = 0;
  logic [7:0] count = 0, mirror;
  int ticks = 0, hits = 0;
  process worker, sampler;
  Base source;
  always #5 clk = ~clk;
  always_ff @(posedge clk) count <= count + 1;
  always_comb mirror = count ^ 8'hff;
  always @(posedge clk) begin
    hits = hits + 1;
    if (sampler == null && source != null) sampler = source.grab();
  end
  initial begin
    static Grabber grabber = new;
    source = grabber;
    fork
      begin
        worker = process::self();
        forever @(posedge clk) ticks = ticks + 1;
      end
    join_none
    #23;
    worker.suspend();
    sampler.kill();
    #20;
    worker.resume();
    #20;
    worker.kill();
    #20;
    $display("count=%0d mirror=%0d ticks=%0d hits=%0d state=%s %s", count,
             mirror, ticks, hits, worker.status().name(),
             sampler.status().name());
    $finish;
  end
endmodule

// PLAN: withheld actor: {{.*}}.sv":34:3) reason=process handle source is runtime-owned
// PLAN: withheld actor: {{.*}}.sv":38:3) reason={{.*}}process control is runtime-owned
// PLAN: withheld actor: {{.*}}.sv":42:7) reason={{.*}}process handle source is runtime-owned
// PLAN: talos eval executor inventory: tier1=2 tier2=0
// PLAN: talos started owners: admitted=2
// CHECK: count=8 mirror=247 ticks=4 hits=2 state=KILLED KILLED
