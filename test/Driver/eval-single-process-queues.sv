// RUN: talos -O3 --vpi=off --mlir-timing %s -o %t.native 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off %s -o %t.two && %t.two > %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -
// RUN: talos -O3 --vpi=off +define+WATCHED %s -o %t.two_owners && %t.two_owners | diff -u %t.out -

module top;
  typedef logic [129:0] word_t;
  word_t history[$];
`ifdef WATCHED
  logic [7:0] watched[$];
  bit ready, woke;
`endif

  function void reset_history();
    history = {};
  endfunction
  task automatic exercise();
    word_t pattern, first, last;
    pattern = {2'b1x, 64'h8000_0000_0000_0001, 64'bz};
    for (int i = 0; i < 8; i++) history.push_back(word_t'(i));
    first = history.pop_front();
    history.push_back(pattern);
    last = history.pop_back();
    if (first !== 0 || last !== pattern || history.size() != 7 ||
        history[0] !== 1 || history[6] !== 7)
      $fatal(1, "packed queue ring");
    reset_history();
    history.push_back(pattern);
    if (history.size() != 1 || history[0] !== pattern)
      $fatal(1, "queue assignment");
  endtask
  initial begin
`ifdef WATCHED
    watched.push_back(0);
    ready = 1;
`endif
    exercise();
    #1;
`ifdef WATCHED
    watched.push_back(7);
`endif
    #1;
`ifdef WATCHED
    if (!woke) $fatal(1, "missed queue wake");
`endif
    $display("packed queue passed");
    $finish;
  end
`ifdef WATCHED
  initial begin
    wait (ready);
    wait (watched.size() == 2);
    woke = 1;
  end
`endif
endmodule
// PLAN: talos single-process queue accesses: {{[1-9][0-9]*}}
// CHECK: packed queue passed
