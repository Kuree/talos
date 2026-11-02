// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 E.4 to E.7: each delay-mode directive sets the mode of every
// module after it, until another one or `resetall; vpiDefDelayMode (47)
// reports it as vpiDelayModeNone (1), Path (2), Distrib (3), Unit (4), Zero (5).
module plain; endmodule
`delay_mode_path
module by_path; endmodule
`delay_mode_distributed
module by_distributed; endmodule
`delay_mode_unit
module by_unit; endmodule
`delay_mode_zero
module by_zero; endmodule
module still_zero; endmodule
`resetall
module after_reset; endmodule

// Anchors come in module-name order: after_reset, by_distributed, by_path,
// by_unit, by_zero, plain, still_zero. after_reset and plain have no record, as
// that is what the runtime reports for none.
// CHECK-NOT: selector = 47 : i32, value = 1 : i32
// CHECK: selector = 47 : i32, value = 3 : i32
// CHECK: selector = 47 : i32, value = 2 : i32
// CHECK: selector = 47 : i32, value = 4 : i32
// CHECK: selector = 47 : i32, value = 5 : i32
// CHECK: selector = 47 : i32, value = 5 : i32
// CHECK-NOT: selector = 47 : i32
