// CLAUSE: Design statement
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 33.5.4: when a configuration is named as the top, only its design cells are roots; the uninstantiated alt is not elaborated as a second top.
// CHECK: TOP RAN
// CHECK-NOT: ALT RAN

module alt; initial $display("ALT RAN"); endmodule
module top; initial $display("TOP RAN"); endmodule
config cfg; design work.top; default liblist work; endconfig
