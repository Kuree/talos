// CLAUSE: Object protection properties: vpiIsProtected is TRUE only for objects from a decryption envelope, whose vpiType stays readable while other access is an error
// XFAIL: *
// Protected envelopes are not implemented (see 34.3): the driver has no key registration or decryption path, so no object can report vpiIsProtected TRUE.
// RUN: %clang -c -fPIC %S/Inputs/37.3.6/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: plain type=vpiIntVar protected=0 name=plain error=0
// CHECK: hidden type=vpiIntVar protected=1 name=null error=1

// Public DES test key: 0123456789abcdef. The envelope holds: module secret; int hidden = 5; endmodule
`pragma protect begin_protected
`pragma protect data_keyowner="lrm-audit"
`pragma protect data_keyname="test-key"
`pragma protect data_method="des-cbc"
`pragma protect encoding=(enctype="base64",line_length=76,bytes=56)
`pragma protect data_block
EjRWeJCrze+tsXJskJDcgJBnkEOkF+YoIxaZDEJTF72pTcI/c5oDxyX86TregU4nrsYREPW1hNk=
`pragma protect end_protected

module top;
int plain = 3;
secret s();
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
