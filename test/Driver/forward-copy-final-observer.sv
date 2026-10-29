// RUN: talos -O3 --top=forward_copy_final_observer --forward-copies=off -G reactive_mode=1 %s -o %t.reactive.base && %t.reactive.base | FileCheck %s
// RUN: talos -O3 --top=forward_copy_final_observer -G reactive_mode=1 %s -o %t.reactive.native && %t.reactive.native | FileCheck %s
// RUN: talos -O3 --top=forward_copy_final_observer --execution-tier=bytecode -G reactive_mode=1 %s -o %t.reactive.bytecode && %t.reactive.bytecode | FileCheck %s
// RUN: talos -O3 --top=forward_copy_final_observer --forward-copies=off -G reactive_mode=0 %s -o %t.final.base && %t.final.base | FileCheck %s
// RUN: talos -O3 --top=forward_copy_final_observer -G reactive_mode=0 %s -o %t.final.native && %t.final.native | FileCheck %s
// RUN: talos -O3 --top=forward_copy_final_observer --execution-tier=bytecode -G reactive_mode=0 %s -o %t.final.bytecode && %t.final.bytecode | FileCheck %s

// IEEE 1800-2023 4.4.2, 4.9.1, 9.2.3 and 20.2: termination begins final
// procedures without running pending Active continuous assignments. Both a
// program's Reactive write immediately before $finish and a write in a final
// procedure leave the copies at their preceding values. Reading the RHS at
// the observer would incorrectly print zero instead of those stored ones.
program final_reactive_writer;
  initial begin
    #1;
    forward_copy_final_observer.source = 1;
    $finish(0);
  end
endprogram

module forward_copy_final_observer #(parameter bit reactive_mode = 1);
  logic source = 0;
  wire net_copy = ~source;
  logic variable_copy;
  assign variable_copy = ~source;

  if (reactive_mode) begin : reactive_case
    final_reactive_writer writer();
  end else begin : final_case
    initial begin
      #1;
      $finish(0);
    end
  end

  final begin
    if (!reactive_mode)
      source = 1;
    $display("source=%b variable=%b net=%b", source, variable_copy, net_copy);
  end
endmodule

// CHECK: source=1 variable=1 net=1
