// IEEE 1800-2023 8.6/8.10/8.20/8.26 and 13.3/13.5.2: recursive,
// non-suspending task calls keep automatic lifetime and immediate ref aliases.
module native_synchronous_class_tasks;
  task automatic leaf(input logic [8:0] value, output logic [8:0] result);
    result = {value[8:1], ~value[0]};
  endtask

  interface class Runner;
    pure virtual task run(ref logic [8:0] value, input int depth,
                          input string tag);
  endclass

  class Base implements Runner;
    int calls;
    string last;
    virtual task run(ref logic [8:0] value, input int depth,
                     input string tag);
      if (depth != 0)
        recurse(value, depth - 1);
      else begin
        leaf(value, value);
        calls++;
        last = tag;
      end
    endtask
    task recurse(ref logic [8:0] value, input int depth);
      if (depth == 0)
        run(value, 0, "R");
      else
        recurse(value, depth - 1);
    endtask
    task combine(ref logic [8:0] first, ref logic [8:0] second);
      first[0] = ~first[0];
      second[0] = ~second[0];
      calls += 4;
    endtask
    static task copy(input logic [8:0] source,
                     output logic [8:0] destination);
      destination = source;
    endtask
  endclass

  class Derived extends Base;
    virtual task run(ref logic [8:0] value, input int depth,
                     input string tag);
      super.run(value, depth, tag);
      calls += 10;
    endtask
    task base_only(ref logic [8:0] value);
      super.run(value, 0, "B");
    endtask
  endclass

  initial begin : call_tasks
    automatic Derived actual = new;
    automatic Base object = actual;
    automatic Runner runner = actual;
    automatic logic [8:0] value = 9'b1xz010101;
    automatic logic [8:0] copied;
    int count;
    if (!$value$plusargs("N=%d", count)) count = 1;
    for (int i = 0; i < count; i++) runner.run(value, 0, "I");
    object.recurse(value, 2);
    actual.base_only(value);
    Base::copy(value, copied);
    object.combine(value, value);
    $display("value=%b copy=%b calls=%0d tag=%s", value, copied,
             actual.calls, actual.last);
  end
endmodule

