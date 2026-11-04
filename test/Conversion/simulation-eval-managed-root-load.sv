// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3 timing=true' -o /dev/null 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --check-prefix=QUIET < %t.trace

// A string, queue, mailbox, semaphore or class object, and a design storage
// root holding one, is never direct state (static specialization admits fixed
// packed integer or logic roots only), so a generated clocked body that reads
// or writes one, even a packed field of such a root, keeps its activation at a
// runtime service checkpoint; so does creating a managed value, or reading one
// through a reference argument. A direct $display beside the access does not
// make that block cold. The build used to stop with "dynamic state load root
// is not direct-state certified" or "generated eval hot closure calls runtime
// symbol talos_rt_v1_gc_current_lane" (IEEE 1800-2023 6.16, 7.10, 15.3, 15.4).
module top;
  logic clk = 0;
  logic [3:0] a = 0;
  string s = "ab";
  int q[$];
  mailbox #(int) mb = new;
  semaphore sem = new(3);
  typedef struct { string s; int k; } pair_t;
  pair_t st;
  int n = 0, m = 0, k = 0, taken = 0, len = 0;
  function automatic int size_of(ref string x); return x.len(); endfunction
  function automatic int field(ref int x); return x; endfunction
  always #5 clk = ~clk;
  // Ordinary packed state stays generated.
  // QUIET-NOT: source=loc("{{.*}}":[[# @LINE + 1]]:
  always_ff @(posedge clk) a <= a + 1;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) if (a[2] && s.len() == 2) n = n + 1;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) if (a[1]) q.push_back(a);
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) void'(mb.try_put(a));
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) if (sem.try_get(1)) taken = taken + 1;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) if (a == 5) begin $display("hit"); len = q.size(); end
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.load source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) m = m + st.k;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.ref.store source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(posedge clk) st.k = a;
  // TRACE-DAG: reason=runtime-state-access operation=simulation.argument_ref.from_ref source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) k = k + size_of(s);
  // TRACE-DAG: reason=runtime-state-access operation=simulation.string.literal source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) begin automatic string t = "xy"; k = k + t.len(); end
  // A packed field of a root that holds a string, passed by reference.
  // TRACE-DAG: reason=runtime-state-access operation=simulation.argument_ref.from_ref source=loc("{{.*}}":[[# @LINE + 1]]:
  always @(negedge clk) k = k + field(st.k);
endmodule
