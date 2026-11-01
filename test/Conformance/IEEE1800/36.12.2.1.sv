// CLAUSE: vpi_compatibility.h
// XFAIL: *
// Selecting the 2017 compatibility macros yields an empty preprocessor condition in the supplied header.
// RUN: %clang -c -fPIC %S/Inputs/36.12.2.1/probe.c -I%resource_dir/include -o %t.helper0.o
