// CLAUSE: system exit status
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.17: $system used as a task still runs the command (its output file holds task_form).
// CHECK: n=1 word=task_form

module top;
  int fd, n;  string word;
  initial begin
    $system("echo task_form > sys.txt");
    fd = $fopen("sys.txt", "r");  n = $fscanf(fd, "%s", word);  $fclose(fd);
    $display("n=%0d word=%s", n, word);
  end
endmodule
