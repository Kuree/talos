// CLAUSE: $save, $restart, and $incsave optional interface
// XFAIL: *
// Optional Annex D interface; the compiler does not implement $save.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins D.9: $save writes a non-empty state file (restoring it in a second run is not covered here).
// CHECK: SAVED n=5 t=3 file=1

module top;
  int n = 1, fd, c;
  initial begin
    n = 5;  #3;
    $save("state.bin");
    fd = $fopen("state.bin", "r");  c = $fgetc(fd);
    $display("SAVED n=%0d t=%0t file=%b", n, $time, c != -1);
  end
endmodule
