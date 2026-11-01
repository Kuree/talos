// CLAUSE: Source-level compatibility include file svdpi_src.h
// XFAIL: *
// The optional SV3.1a svdpi_src.h compatibility header is not supplied.
// RUN: %clang -c -fPIC %S/Inputs/H.14.3/probe.c -I%resource_dir/include -o %t.helper0.o
