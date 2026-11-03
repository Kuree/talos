// UNSUPPORTED: windows
// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 %s -o sim && ./sim | FileCheck %s

// IEEE 1800-2023 D.8: the run after a $reset starts from the initial state, so
// it inherits no descriptor an earlier run opened: not the one the runtime
// opened to restart itself, nor a file the design opened, a log (D.7) or a
// dump file (21.7). A program $system starts (20.18) is not part of a reset
// either.
module top;
  int first, last, file;
  string seen;
  initial begin
    file = $fopen($sformatf("out.%0d", $reset_count), "w");
    $log($sformatf("log.%0d", $reset_count));
    $dumpfile($sformatf("dump.%0d.vcd", $reset_count));
    $dumpvars;
    void'($system($sformatf("ls /dev/fd | wc -l > fds.%0d", $reset_count)));
    if ($reset_count < 2) $reset(0, 3);
    void'($system("echo ${TALOS_RESET_COUNT:-unset}${TALOS_RESET_VALUE:-unset}${TALOS_RESET_INTERACTIVE:-unset} > env"));
    file = $fopen("fds.0", "r");
    void'($fscanf(file, "%d", first));
    $fclose(file);
    file = $fopen("fds.2", "r");
    void'($fscanf(file, "%d", last));
    $fclose(file);
    file = $fopen("env", "r");
    void'($fscanf(file, "%s", seen));
    $fclose(file);
    $display("same descriptors=%0d", first == last && first > 0);
    $display("child reset count=%s", seen);
    $finish;
  end
endmodule

// CHECK: same descriptors=1
// CHECK-NEXT: child reset count=unsetunsetunset
