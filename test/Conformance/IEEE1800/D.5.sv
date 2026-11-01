// CLAUSE: $key and $nokey optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.5: $key("file") creates the named key file.
// CHECK: KEYFILE=1

module top;
  int fd;
  initial begin
    $key("key.log");  $nokey;  $key;
    fd = $fopen("key.log", "r");
    $display("KEYFILE=%0d", fd != 0);
  end
endmodule
