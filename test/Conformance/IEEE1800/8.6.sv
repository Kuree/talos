// CLAUSE: Methods act on their own object with automatic locals; a method with static lifetime is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.6/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: class methods cannot have static lifetime
// CHECK: 4 8{{$}}
// CHECK-NEXT: automatic 1 6 8{{$}}

// 8.6: a method changes only its own object, and each call gets fresh locals.
class Packet;
  int status = 0;
  function int current_status();
    return status;
  endfunction
  function void set(int s);
    status = s;
  endfunction
  function int bump();
    int step = 0;
    step++;
    status += step;
    return step;
  endfunction
endclass
module top;
  Packet p, q;
  initial begin
    p = new;
    q = new;
    p.set(4);
    q.set(8);
    $display("%0d %0d", p.current_status(), q.current_status());
    void'(p.bump());
    $display("automatic %0d %0d %0d", p.bump(), p.status, q.status);
    $finish;
  end
endmodule
