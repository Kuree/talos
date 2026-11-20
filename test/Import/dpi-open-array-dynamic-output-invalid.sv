// RUN: not talos %s -o %t 2>&1 | FileCheck %s
// RUN: not talos -DQUEUE -emit-sim %s -o %t 2>&1 | FileCheck %s --check-prefix=QUEUE

module dpi_open_array_dynamic_output_invalid;
  import "DPI-C" task invalid(output int values[]);
`ifdef QUEUE
  int values[$];
`else
  int values[];
`endif

  initial invalid(values);
endmodule

// CHECK: dynamic-array and queue actuals cannot be passed to an output DPI open-array formal with unsized dimensions
// QUEUE: error: {{(value of type 'int\$\[\]' cannot be assigned to type 'int\$\[\$\]'|dynamic-array and queue actuals cannot be passed to an output DPI open-array formal)}}
