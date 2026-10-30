// RUN: talos-opt --split-input-file --verify-diagnostics %s
module {
  simulation.func @zero(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %target: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32} {
    // expected-error @+1 {{requires a positive width matching the packed integral target}}
    simulation.power.cancel_nba %ctx, %target width 0 : !simulation.ref<!simulation.logic<1>>
    simulation.return
  }
}
// -----
module {
  simulation.func @mismatch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %target: !simulation.ref<i8> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32} {
    // expected-error @+1 {{requires a positive width matching the packed integral target}}
    simulation.power.cancel_nba %ctx, %target width 7 : !simulation.ref<i8>
    simulation.return
  }
}
// -----
module {
  simulation.func @negative(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %target: !simulation.ref<i8> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32} {
    // expected-error @+1 {{requires a positive width matching the packed integral target}}
    simulation.power.cancel_nba %ctx, %target width -1 : !simulation.ref<i8>
    simulation.return
  }
}
// -----
module {
  simulation.func @real(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %target: !simulation.ref<f64> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32} {
    // expected-error @+1 {{requires a positive width matching the packed integral target}}
    simulation.power.cancel_nba %ctx, %target width 64 : !simulation.ref<f64>
    simulation.return
  }
}
