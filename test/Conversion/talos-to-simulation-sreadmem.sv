// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 D.14: $sreadmem* read their strings as one $readmem stream,
// with the memory first and start/finish as the second and third arguments.
module top;
  typedef enum logic [1:0] {A = 1, B = 2} e_t;
  logic [7:0] h[0:3];
  logic [3:0] b[3:0];
  e_t em[0:1];
  string s = "ab";
  initial begin
    $sreadmemh(h, 1, 3, "12 34", s);
    $sreadmemb(b, 3, 0, "1010");
    $sreadmemh(em, 0, 1, "1 2");
  end
endmodule

// The enum memory's legal words A and B are materialized for the data check,
// so the memory is found as the first argument.
// CHECK: simulation.logic.constant -2 : i2, 0 : i2
// CHECK: simulation.logic.constant 1 : i2, 0 : i2
// A string-backed stream joins the strings with a line break.
// CHECK: %[[SEP:.*]] = simulation.string.literal "\0A"
// CHECK: %[[JOIN:.*]] = simulation.string.concat {{.*}}%[[SEP]]
// CHECK: simulation.file.open_string %arg0, %[[JOIN]], %{{.*}}
// CHECK: simulation.file.readmem_token %arg0, %{{.*}} {radix = #simulation.radix<hex>}
// A single string needs no concatenation and $sreadmemb reads binary.
// CHECK-NOT: simulation.string.concat
// CHECK: simulation.file.open_string
// CHECK: simulation.file.readmem_token {{.*}} {radix = #simulation.radix<binary>}
// CHECK: simulation.file.open_string
// CHECK: simulation.file.readmem_token {{.*}} {radix = #simulation.radix<hex>}
