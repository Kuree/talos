// CLAUSE: fgets line
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 21.3.6: data written is visible through a second descriptor right after $fflush(fd) and $fflush() with no argument, before any $fclose.
// CHECK: F1 n=6 ok=1
// CHECK: F2 n=6,7 ok=1,1

module top;
  int fd, rd1, rd2, n1, n2, n3;  string l1, l2, l3;
  initial begin
    fd = $fopen("fl.txt", "w");  $fwrite(fd, "first\n");  $fflush(fd);
    rd1 = $fopen("fl.txt", "r");  n1 = $fgets(l1, rd1);
    $display("F1 n=%0d ok=%b", n1, l1 == "first\n");
    $fwrite(fd, "second\n");  $fflush();
    rd2 = $fopen("fl.txt", "r");  n2 = $fgets(l2, rd2);  n3 = $fgets(l3, rd2);
    $display("F2 n=%0d,%0d ok=%b,%b", n2, n3, l2 == "first\n", l3 == "second\n");
    $fclose(fd);
  end
endmodule
