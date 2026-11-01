// CLAUSE: svdpi.h definitions for SV3.1a-style packed data processing
// XFAIL: *
// The optional legacy SV3.1a canonical types/macros are not supplied.
// RUN: %clang -c -fPIC %S/Inputs/H.14.2/probe.c -I%resource_dir/include -o %t.helper0.o
