// CLAUSE: configuration selection
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module existing; endmodule
config selected_config;
  design work.missing;
  default liblist work;
endconfig
