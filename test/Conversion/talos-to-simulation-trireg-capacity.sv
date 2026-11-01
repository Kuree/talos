// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 E.3: the integer places a trireg net without a declared charge
// strength among the strength levels, and orders the nets within one of them. A
// declared strength wins over the directive and has no integer.
`default_trireg_strength 1
module c1; trireg t; trireg (large) declared; endmodule
`default_trireg_strength 3
module c3; trireg t; endmodule
`default_trireg_strength 200
module c200; trireg t; endmodule
`resetall
module top; c1 a(); c3 b(); c200 c(); endmodule

// CHECK: simulation.net.decl {{.*}}hierarchy "top.a.t" {{.*}}charge_strength = 1 : i32{{.*}}default_trireg_strength = 1 : i32
// CHECK: simulation.net.decl {{.*}}hierarchy "top.a.declared" {{.*}}charge_strength = 4 : i32
// CHECK-NOT: default_trireg_strength{{.*}}top.b
// CHECK: simulation.net.decl {{.*}}hierarchy "top.b.t" {{.*}}charge_strength = 2 : i32{{.*}}default_trireg_strength = 3 : i32
// CHECK: simulation.net.decl {{.*}}hierarchy "top.c.t" {{.*}}charge_strength = 4 : i32{{.*}}default_trireg_strength = 200 : i32
