// RUN: talos -O0 %s -o %t.native-o0
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native-o0 | FileCheck %s
// RUN: talos -O3 %s -o %t.native-o3
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native-o3 | FileCheck %s
// RUN: talos -O3 --execution-tier=bytecode %s -o %t.bytecode
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.bytecode | FileCheck %s

// A task's arguments are copied into the task's own storage when it is called
// (IEEE 1800-2023 13.5.1; inout copies in at the call and out at the return,
// 13.3), and objects, strings and dynamic and associative arrays stay alive
// while anything can reach them (8.29). A caller writes those copies into the
// task's frame before the task first runs, and another process can run (and
// the scheduler collect at its activation boundary) before then, so the frame
// must be traced from the moment the task is created. A threshold of one byte
// collects at every such point.

module native_task_container_arguments_gc;
  task automatic take_input
      (input int values[$]);
    int copy[$];
    copy = values;
    copy.push_back(3);
    $display("input copy=%p values=%p", copy, values);
  endtask

  task automatic update_inout
      (inout int values[string]);
    values["inout"] = 22;
  endtask

  task automatic show_later
      (input int values[$]);
    #1;
    $display("later values=%p", values);
  endtask

  initial begin
    int queue[$];
    int keyed[string];
    queue.push_back(11);
    take_input(queue);
    keyed["before"] = 11;
    update_inout(keyed);
    show_later(queue);
    $display("after queue=%p keyed=%p", queue, keyed);
  end

  // Runs between the first task call and the callee's first activation
  // (both initial processes start in the Active region; 4.7 allows either
  // order), allocating over the callee's freed argument if it was not traced.
  initial begin
    int other[$];
    other.push_back(22);
    $display("other=%p", other);
  end

  // CHECK-DAG: other='{22}
  // CHECK-DAG: input copy='{11, 3} values='{11}
  // CHECK: later values='{11}
  // CHECK-NEXT: after queue='{11} keyed='{"before":11, "inout":22}
endmodule
