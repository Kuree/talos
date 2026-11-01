// CLAUSE: cell qualified liblist error
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=selected_config -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module leaf;endmodule module top;leaf a();endmodule
config selected_config;design work.top;default liblist work;cell work.leaf liblist work;endconfig
