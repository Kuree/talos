// CLAUSE: randomize through an interface class handle honors object constraints; constraints in one are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.9/constraint.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.9/covergroup.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: member not allowed in interface class declaration
// DIAG: member not allowed in interface class declaration
// CHECK: result 1 value 9 pre 1 post 1{{$}}

// 8.26.9: the object's constraint and its overridden pre and post methods apply though the call goes through Src.
interface class Src;
  pure virtual function int id();
endclass
class Impl implements Src;
  rand bit [3:0] v;
  int pre = 0, post = 0;
  constraint c { v == 9; }
  virtual function int id();
    return v;
  endfunction
  function void pre_randomize();
    pre++;
  endfunction
  function void post_randomize();
    post++;
  endfunction
endclass
module top;
  Impl h;
  Src s;
  int r;
  initial begin
    h = new;
    s = h;
    r = s.randomize();
    $display("result %0d value %0d pre %0d post %0d", r, s.id(), h.pre, h.post);
    $finish;
  end
endmodule
