// CLAUSE: system exit status
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.17.1: $system runs the command (side-effect file read back) and returns its status (0 for exit 0, nonzero for exit 3).
// CHECK: rc0=0 rc3_nonzero=1 line=made

module top;
  int rc0, rc3, fd;  string line;
  initial begin
    rc0 = $system("exit 0");
    rc3 = $system("exit 3");
    void'($system("echo made > sys17.txt"));
    fd = $fopen("sys17.txt", "r");  void'($fgets(line, fd));  $fclose(fd);
    $display("rc0=%0d rc3_nonzero=%b line=%s", rc0, rc3 != 0, line);
  end
endmodule
