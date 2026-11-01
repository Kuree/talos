// CLAUSE: VPI compatibility
// XFAIL: *
// Selecting the 2017 compatibility macros yields an empty preprocessor condition in the supplied header.
// RUN: %clang -c -fPIC %S/Inputs/L/probe.c -I%resource_dir/include -o %t.helper0.o
