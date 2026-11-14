// RUN: talos --std=1800-2023 -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-edit-attributes=op=talos.sv.symbol.class_property match={name = "taken"} set={rand_mode = 0 : i32}' '--test-talos-edit-attributes=op=talos.sv.symbol.class_property match={name = "excluded"} set={rand_mode = 0 : i32}' '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' '--lower-talos-to-sim=opt-level=0' '--encode-talos-sim-to-bytecode=vpi=off' --convert-talos-sim-processes-to-llvm-coroutines | talos-translate --mlir-to-llvmir | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --seed=13 | FileCheck %s
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.4: a unique group may mix random leaves with state
// (non-rand) array leaves and a state real. State leaves exclude values but
// are never changed; duplicate state leaves make the solve fail; real
// uniqueness is numeric (+0.0 conflicts with -0.0). Slang rejects non-rand
// operands (see the *-slang-xfail.sv tests), so the RUN line flips the
// `rand` property mode of taken/excluded off after import.
// CHECK: unique state array PASS
// CHECK-NEXT: unique state duplicate PASS
// CHECK-NEXT: unique state real PASS

class A;
  rand bit [1:0] values[2];
  rand bit [1:0] taken[2];
  constraint distinct { unique {values, taken}; }
endclass

class R;
  rand real value;
  rand real excluded;
  constraint fixed { value == 0.0; }
  constraint distinct { unique {value, excluded}; }
endclass

module t;
  initial begin
    static A a = new;
    static R r = new;
    bit [1:0] seen;

    
    a.taken[0] = 1; a.taken[1] = 2;
    repeat (16) begin
      if (!a.randomize()) $fatal(1, "array randomize failed");
      if (!((a.values[0] == 0 && a.values[1] == 3) ||
            (a.values[0] == 3 && a.values[1] == 0)))
        $fatal(1, "values not {0,3}: %0d %0d", a.values[0], a.values[1]);
      if (a.taken[0] != 1 || a.taken[1] != 2) $fatal(1, "state changed");
      seen[a.values[0] == 0] = 1;
    end
    if (seen != 2'b11) $fatal(1, "missing arrangement");
    a.taken[0] = 0; a.taken[1] = 3;
    repeat (16) begin
      if (!a.randomize()) $fatal(1, "array randomize 2 failed");
      if (a.values[0] + a.values[1] != 3 || a.values[0] == 0 || a.values[0] == 3)
        $fatal(1, "values not {1,2}");
    end
    $display("unique state array PASS");

    a.values[0] = 2; a.values[1] = 1;
    a.taken[0] = 1; a.taken[1] = 1;
    if (a.randomize()) $fatal(1, "duplicate state leaves solved");
    if (a.values[0] != 2 || a.values[1] != 1) $fatal(1, "failed solve modified values");
    $display("unique state duplicate PASS");

    
    r.excluded = -0.0;
    if (r.randomize()) $fatal(1, "+0.0 unique against -0.0 solved");
    r.excluded = 1.0;
    if (!r.randomize()) $fatal(1, "real randomize failed");
    if (r.value != 0.0 || r.excluded != 1.0) $fatal(1, "real values changed");
    $display("unique state real PASS");
  end
endmodule
