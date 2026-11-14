// RUN: %talos --std=1800-2023 -O0 -o %t %s
// RUN: %t --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 12.7.1 and 18.5.11: for loops with constant bounds and
// ++/--/+=K strides in a constraint function are expanded into the solver
// relation. Signed counters, modular wrap, mixed-signedness comparisons
// (11.8.2), a 130-bit counter, break/continue and zero-trip loops must give
// the same result as ordinary function execution.
// CHECK: procedural loops PASS
// CHECK-NEXT: popcount loop PASS
// CHECK-NEXT: scope loops PASS

function automatic int pop4(bit [3:0] value);
  int count = 0;
  for (int i = 0; i < 4; ++i) count += (value >> i) & 1;
  return count;
endfunction

// Returns value when every loop below ran the expected number of trips.
function automatic bit identity(bit value);
  int i, count = 0;
  for (i = 3; i >= -1; i--) count++;                         // 5 trips
  if (count != 5 || i != -2) return !value;
  count = 0;
  for (i = 0; 3 > i; i++) begin if (i == 1) continue; count++; end
  if (count != 2 || i != 3) return !value;
  count = 0;
  for (bit [1:0] j = 3; j != 1; j++) count++;                // 3, 0 : wraps
  if (count != 2) return !value;
  count = 0;
  for (bit [7:0] k = 0; k < 3; k += 257) count++;            // step is 1
  if (count != 3) return !value;
  count = 0;
  for (bit signed [3:0] s = -3; s < 4'd3; s++) count++;      // unsigned: 13<3
  if (count != 0) return !value;
  for (bit signed [3:0] s = -3; s < 3; s++) count++;         // signed: 6 trips
  if (count != 6) return !value;
  count = 0;
  for (bit signed [129:0] w = 6; w > 0; w -= 2) count++;     // 3 trips
  if (count != 3) return !value;
  for (i = 0; i < -1; ++i) return !value;                    // zero trips
  count = 0;
  for (i = 0; i <= 2; i++) begin
    for (int j = 0; j != 3; ++j) begin count++; break; end
    if (i == 1) break;
  end
  if (count != 2 || i != 1) return !value;
  return value;
endfunction

class C;
  rand bit [2:0] x;
  rand bit [3:0] y;
  constraint relation { x == pop4(y); y inside {0, 3, 15, 8}; }
endclass

module top;
  C object = new;
  bit valid = 1, a, b;
  initial begin
    for (int v = 0; v < 16; ++v)
      if (pop4(v) != $countones(4'(v))) $fatal(1, "pop4(%0d) wrong", v);
    if (identity(1'b1) !== 1'b1 || identity(1'b0) !== 1'b0)
      $fatal(1, "identity wrong");
    $display("procedural loops PASS");
    repeat (64) begin
      if (!object.randomize()) $fatal(1, "randomize failed");
      if (object.x != $countones(object.y)) $fatal(1, "x != popcount(y)");
    end
    $display("popcount loop PASS");
    repeat (64) begin
      if (!std::randomize(a, b) with { a == identity(b); })
        $fatal(1, "scope randomize failed");
      if (a != b) $fatal(1, "identity relation broken");
    end
    $display("scope loops PASS");
  end
endmodule
