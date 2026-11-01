// CLAUSE: Backward SAIF header
// REQUIRES: upf
// XFAIL: *
// capability-unavailable
// Prerequisite: SAIF is an external exchange format; the compiler advertises no SAIF import/export entry point, so this production cannot be exercised.
// RUN: %talos --help-hidden
// CHECK-DAG: {{[Ss][Aa][Ii][Ff]}}
