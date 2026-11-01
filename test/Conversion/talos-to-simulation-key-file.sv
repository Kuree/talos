// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 D.5: $key(file) creates a new key file; $nokey and $key
// without a name only toggle output to it, so they generate no file access.
module top;
  initial begin
    $key("key.log");
    $nokey;
    $key;
  end
endmodule

// CHECK: simulation.file.open_string
// CHECK: simulation.file.close
// CHECK-NOT: simulation.file
