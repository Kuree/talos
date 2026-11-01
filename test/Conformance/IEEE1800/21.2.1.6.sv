// CLAUSE: p unpacked struct
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 21.2.1.6: %p prints named struct elements (packed struct nested), enum names (base value if invalid), quoted strings, only the first union member, null handles, array patterns.
// CHECK: S='{count:3,{{ *}}valid:1,{{ *}}name:"ab",{{ *}}c:GREEN,{{ *}}p:'{hi:10,{{ *}}lo:5}}
// CHECK: A='{1,{{ *}}2,{{ *}}3}
// CHECK: H=null
// CHECK: B=5
// CHECK: U='{i:7}
// CHECK: AA='{"x":1,{{ *}}"y":2}

typedef enum {RED, GREEN} color_t;
typedef struct packed {logic [3:0] hi; logic [3:0] lo;} P;
typedef struct {int count; bit valid; string name; color_t c; P p;} Payload;
typedef union {int i; real r;} UU;
class K; endclass
module top;
  Payload v = '{count:3, valid:1, name:"ab", c:GREEN, p:'{hi:4'ha, lo:4'h5}};
  int arr[3] = '{1, 2, 3};  K h = null;  color_t bad;  UU u;  int aa[string];
  initial begin
    bad = color_t'(5);  u.i = 7;  aa["x"] = 1;  aa["y"] = 2;
    $display("S=%p", v);  $display("A=%p", arr);  $display("H=%p", h);
    $display("B=%p", bad);  $display("U=%p", u);  $display("AA=%p", aa);
  end
endmodule
