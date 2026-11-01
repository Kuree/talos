// CLAUSE: defaults evaluated at call
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

  int seed=1,calls=0;
  function automatic int next(); calls++; return seed; endfunction
  function automatic int f(input int a=next()); return a; endfunction
  int a,b,c;

initial begin

  a=f(); seed=2; b=f(); c=f(99);
  if(a!=1 || b!=2 || c!=99 || calls!=2) $fatal(1,"defaults a=%0d b=%0d c=%0d calls=%0d",a,b,c,calls);

$display("PASS");
$finish;
end
endmodule
