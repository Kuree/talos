// CLAUSE: Configuration design selects a source unit
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 -O3 --execution-tier=%tier --top=choice %s -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module selected;initial $display("PASS");endmodule
module ignored;initial $fatal(1,"wrong root");endmodule
config choice;design work.selected;default liblist work;endconfig
