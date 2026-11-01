// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -DWRITES_INPUT -emit-slang %s | not talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s --check-prefix=WRITES-INPUT

module top;
  bit clk, one = 1;

  // IEEE 1800-2023 16.8.2, 16.12.19: an input local formal starts each attempt
  // with the value of its actual argument.
  property input_formal(local input int v);
    one ##1 v == 3;
  endproperty
  a: assert property (@(posedge clk) input_formal(3));

  // IEEE 1800-2023 16.8.2: an output local formal of a nested sequence reaches
  // its actual, a local of the enclosing property, when the sequence matches.
  sequence writes(local output int v);
    (one, v = 9);
  endsequence
  property output_formal;
    int saved;
    writes(saved) ##1 saved == 9;
  endproperty
  b: assert property (@(posedge clk) output_formal);

`ifdef WRITES_INPUT
  // An assignment to an input formal does not reach its actual, while the
  // bounded monitor shares one cell between them.
  sequence changes(local input int v);
    // WRITES-INPUT: error: assigning to an input local formal of a nested assertion instance is not executable by the bounded monitor
    (one, v = v + 1);
  endsequence
  property keeps;
    int kept = 5;
    changes(kept) ##1 kept == 5;
  endproperty
  c: assert property (@(posedge clk) keeps);
`endif
endmodule

// The local is compared one cycle later, and a matched attempt carries it.
// CHECK-LABEL: simulation.func private @unit_1(
// CHECK: ^bb2({{.*}}: i64, [[LOCAL:%[0-9]+]]: i32):
// CHECK: [[EXPECTED:%[a-z0-9_]+]] = arith.constant {simulation.rematerialized} 3 : i32
// CHECK: arith.cmpi ne, [[LOCAL]], [[EXPECTED]] : i32
// CHECK: [[ACTUAL:%[a-z0-9_]+]] = arith.constant {simulation.rematerialized} 3 : i32
// CHECK: cf.cond_br {{.*}}^bb1({{.*}}, [[ACTUAL]] : i64, i32), ^bb1

// CHECK-LABEL: simulation.func private @unit_2(
// CHECK: ^bb2({{.*}}: i64, [[SAVED:%[0-9]+]]: i32):
// CHECK: [[WRITTEN:%[a-z0-9_]+]] = arith.constant {simulation.rematerialized} 9 : i32
// CHECK: arith.cmpi ne, [[SAVED]], [[WRITTEN]] : i32
// CHECK: [[ASSIGNED:%[a-z0-9_]+]] = arith.constant {simulation.rematerialized} 9 : i32
// CHECK: cf.cond_br {{.*}}^bb1({{.*}}, [[ASSIGNED]] : i64, i32), ^bb1
