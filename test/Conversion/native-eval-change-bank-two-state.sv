// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3' --mlir-print-ir-after=materialize-native-processes -o /dev/null 2>&1 | FileCheck %s --check-prefix=FOUR
// RUN: talos -emit-slang %s | talos-opt '--test-talos-set-module-attributes=attrs="{native.two_state}"' --test-talos-native-backend='scheduler=eval sim-opt-level=3' --mlir-print-ir-after=materialize-native-processes -o /dev/null 2>&1 | FileCheck %s --check-prefix=TWO --implicit-check-not=change_bank_0.unknown

// Two nonblocking assignments to all of a wide root whose watchers wait only
// for a change stage the complete value in a whole-value change bank (IEEE
// 1800-2023 4.6(b), 9.4.2, 10.4.2). A four-state bank also keeps the X/Z
// words of the value, compares them with the staged ones and stores them. A
// two-state executable has no X/Z bits (6.11.2): its bank has no X/Z words,
// its slot passes a null unknown array, which the runtime reads as zero in a
// two-state executable, and its captures neither compare nor store X/Z bits.

module top;
  bit clk;
  logic rst_n = 0;
  logic [99:0] q = '0, first = '0, last = '0;
  int low, high, failures;
  always #5 clk = !clk;
  always @(posedge clk) begin
    q <= first;
    q <= last;
  end
  always @(q[2]) low++;
  always @(q[99]) high++;
  a: assert property (@(posedge clk) disable iff (!rst_n) rst_n |=> rst_n) else failures++;
  initial begin
    #1 rst_n = 1;
    first[2] = 1;
    #10 last = first;
    #10 $display("%0d %0d %0d", low, high, failures);
    $finish;
  end
endmodule

// FOUR-LABEL: IR Dump After MaterializeNativeProcessesPass
// FOUR: llvm.mlir.global internal constant @__talos_eval_nba_change_bank_0.slot()
// FOUR: %[[UNKNOWN:.*]] = llvm.mlir.addressof @__talos_eval_nba_change_bank_0.unknown
// FOUR-NEXT: llvm.insertvalue %[[UNKNOWN]], %{{.*}}[2]
// FOUR: llvm.mlir.global internal @__talos_eval_nba_change_bank_0.unknown() {{.*}} : !llvm.array<2 x i64>
// FOUR: %[[VALUES:.*]] = llvm.mlir.addressof @__talos_eval_nba_change_bank_0.value
// FOUR-NEXT: %[[UNKNOWNS:.*]] = llvm.mlir.addressof @__talos_eval_nba_change_bank_0.unknown
// FOUR-NEXT: %[[VALUE:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i100
// FOUR-NEXT: %[[XZ:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i100
// FOUR: llvm.load %[[UNKNOWNS]] {alignment = 8 : i64} : !llvm.ptr -> i100
// FOUR: llvm.store %[[VALUE]], %[[VALUES]] {alignment = 8 : i64} : i100, !llvm.ptr
// FOUR-NEXT: llvm.store %[[XZ]], %[[UNKNOWNS]] {alignment = 8 : i64} : i100, !llvm.ptr

// TWO-LABEL: IR Dump After MaterializeNativeProcessesPass
// TWO: llvm.mlir.global internal constant @__talos_eval_nba_change_bank_0.slot()
// TWO: llvm.mlir.addressof @__talos_eval_nba_change_bank_0.value
// TWO-NEXT: llvm.insertvalue %{{.*}}[1]
// TWO-NEXT: %[[NULL:.*]] = llvm.mlir.zero : !llvm.ptr
// TWO-NEXT: llvm.insertvalue %[[NULL]], %{{.*}}[2]
// TWO-NEXT: llvm.mlir.addressof @__talos_eval_nba_change_bank_0.valid
// TWO: %[[VALUES:.*]] = llvm.mlir.addressof @__talos_eval_nba_change_bank_0.value
// TWO-NEXT: %[[VALUE:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i100
// TWO-NEXT: llvm.mlir.addressof @__talos_eval_nba_change_bank_0.valid
// TWO: %[[PRIOR:.*]] = llvm.load %[[VALUES]] {alignment = 8 : i64} : !llvm.ptr -> i100
// TWO-NEXT: %[[DELTA:.*]] = llvm.xor %[[VALUE]], %[[PRIOR]] : i100
// TWO-NEXT: llvm.mlir.addressof @__talos_eval_nba_change_bank_0.transient
// TWO: llvm.or %[[DELTA]], %{{.*}} : i100
// TWO: llvm.store %[[VALUE]], %[[VALUES]] {alignment = 8 : i64} : i100, !llvm.ptr
// TWO-NEXT: llvm.mlir.constant(2 : i32) : i32
