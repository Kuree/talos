// CLAUSE: advertised negative timing-check invocation control
// XFAIL: *
// Published compiler options do not expose negative timing-check invocation control.
// RUN: %talos --help-hidden
// CHECK-DAG: {{[Nn]egative.*[Tt]iming|[Tt]iming.*[Cc]heck.*[Oo]ption}}
