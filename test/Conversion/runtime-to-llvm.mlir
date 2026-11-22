// RUN: talos-opt --convert-talos-runtime-to-llvm %S/../IR/runtime.mlir | FileCheck %s
// RUN: talos-opt --prepare-runtime-to-llvm --convert-runtime-to-llvm %S/../IR/runtime.mlir | FileCheck %s

// Every runtime call is declared from its catalog row: the prototype, the
// entry and, only for an entry the catalog marks Cold (a diagnostic or
// termination service), the cold attribute.
// CHECK-DAG: llvm.func @talos_rt_v1_context_create(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<context_create>}
// CHECK-DAG: llvm.func @talos_rt_v1_context_destroy(!llvm.ptr) attributes {native.runtime_entry = #native.runtime_entry<context_destroy>}
// CHECK-DAG: llvm.func @talos_rt_v1_status_string(i32) -> !llvm.ptr attributes {native.runtime_entry = #native.runtime_entry<status_string>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_buffer_release(!llvm.ptr) attributes {native.runtime_entry = #native.runtime_entry<buffer_release>}
// CHECK-DAG: llvm.func @talos_rt_v1_last_error(!llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<last_error>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_finish(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_finish>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_stop(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_stop>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_fatal(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_fatal>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_error(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_error>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_publication_batch_begin(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_publication_batch_begin>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_publication_batch_end(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_publication_batch_end>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_termination_requested(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_termination_requested>}
// CHECK-DAG: llvm.func @talos_rt_v1_format(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<format>}
// CHECK-DAG: llvm.func @talos_rt_v1_string_output_format(!llvm.ptr, i32, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<string_output_format>}
// CHECK-DAG: llvm.func @talos_rt_v1_display(!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<display>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_time_scan_scale(!llvm.ptr, f64, i64, i32) -> f64 attributes {native.runtime_entry = #native.runtime_entry<time_scan_scale>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_open_mcd(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_open_mcd>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_open(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_open>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_close(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_close>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_flush(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_flush>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_write(!llvm.ptr, i32, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_write>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_read(!llvm.ptr, i32, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_read>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_readmem_token(!llvm.ptr, i32, i32, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_readmem_token>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_getc(!llvm.ptr, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_getc>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_ungetc(!llvm.ptr, i32, i8) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_ungetc>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_getline(!llvm.ptr, i32, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_getline>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_eof(!llvm.ptr, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_eof>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_error(!llvm.ptr, i32, !llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_error>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_file_seek(!llvm.ptr, i32, i64, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_seek>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_tell(!llvm.ptr, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_tell>}
// CHECK-DAG: llvm.func @talos_rt_v1_file_rewind(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<file_rewind>}
// CHECK-DAG: llvm.func @talos_rt_v1_fragment_execute(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<fragment_execute>}
// CHECK-DAG: llvm.func @talos_rt_v1_bytecode_execute_bounded(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i32, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<bytecode_execute_bounded>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_program_exit(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_program_exit>, passthrough = ["cold"]}
// CHECK-DAG: llvm.func @talos_rt_v1_gc_collect_pending(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<gc_collect_pending>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_program_owned(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_program_owned>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_time(!llvm.ptr) -> i64 attributes {native.runtime_entry = #native.runtime_entry<scheduler_time>}
// CHECK-DAG: llvm.func @talos_rt_v1_scheduler_cohort(!llvm.ptr) -> i64 attributes {native.runtime_entry = #native.runtime_entry<scheduler_cohort>}
// CHECK-DAG: llvm.func @talos_rt_v1_string_output_fields(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<string_output_fields>}
// CHECK-DAG: llvm.func @talos_rt_v1_time_format(!llvm.ptr, i32, i32, !llvm.ptr, i64, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<time_format>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_open(!llvm.ptr, !llvm.ptr, i64) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_open>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_timescale(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_timescale>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_vars(!llvm.ptr, i64, !llvm.ptr, i64) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_vars>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_all(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_all>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_control(!llvm.ptr, i32) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_control>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_limit(!llvm.ptr, i64) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_limit>}
// CHECK-DAG: llvm.func @talos_rt_v1_dump_flush(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<dump_flush>}

// CHECK: func.func private @abi_records(!llvm.struct<(i32, i32, i64)>, !llvm.struct<(i32, i32, i32, i32, i64, i64)>, !llvm.ptr, !llvm.ptr, !llvm.struct<(i32, i32)>, !llvm.struct<(i32, i32)>, !llvm.struct<(i8, i8, i8, i8, i32, i64, i64, i64)>, !llvm.struct<(i32, i32, i16, i16, i32)>, i8, i8, i8, i8, i8, i32, !llvm.struct<(i32, i32, i64, ptr, ptr)>, !llvm.ptr)
// CHECK: func.func private @identity(!llvm.ptr) -> !llvm.ptr
// CHECK: func.func private @tuple_identity(tuple<!llvm.ptr>) -> tuple<!llvm.ptr>
// CHECK-LABEL: func.func @call_indirect
// CHECK: %[[CALLEE:.*]] = constant @identity : (!llvm.ptr) -> !llvm.ptr
// CHECK: %[[RESULT:.*]] = call_indirect %[[CALLEE]]({{.*}}) : (!llvm.ptr) -> !llvm.ptr
// CHECK: return %[[RESULT]] : !llvm.ptr
// CHECK-LABEL: func.func @call_and_branch
// CHECK: call @identity({{.*}}) : (!llvm.ptr) -> !llvm.ptr
// CHECK: cf.cond_br {{.*}}, ^bb1({{.*}} : !llvm.ptr), ^bb2({{.*}} : !llvm.ptr)
// CHECK-LABEL: func.func @loop_alloca
// CHECK: llvm.alloca {{.*}} x i8 {alignment = 1 : i64}
// CHECK: cf.br
// CHECK: ^bb1:
// CHECK-NOT: llvm.alloca
// CHECK: llvm.call @talos_rt_v1_file_getc
// CHECK-LABEL: func.func @managed_object_argument
// CHECK: llvm.mlir.constant(7 : i32) : i32
// CHECK: llvm.insertvalue
// CHECK-LABEL: func.func @virtual_interface_argument
// CHECK: llvm.mlir.constant(8 : i32) : i32
// CHECK: llvm.insertvalue
// CHECK-LABEL: func.func @runtime_calls
// CHECK-DAG: llvm.alloca {{.*}} x !llvm.ptr {alignment = 8 : i64}
// CHECK-DAG: llvm.alloca {{.*}} x i8 {alignment = 1 : i64}
// CHECK-DAG: llvm.alloca {{.*}} x !llvm.struct<(i32, i32, i32, i32, i64, i64)> {alignment = 8 : i64}
// CHECK: llvm.call @talos_rt_v1_context_create
// CHECK: llvm.load {{.*}} {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @talos_rt_v1_scheduler_finish
// CHECK: llvm.call @talos_rt_v1_scheduler_stop
// CHECK: llvm.call @talos_rt_v1_scheduler_fatal
// CHECK: llvm.call @talos_rt_v1_scheduler_error
// CHECK: llvm.call @talos_rt_v1_scheduler_publication_batch_begin
// CHECK: llvm.call @talos_rt_v1_scheduler_publication_batch_end
// CHECK: %[[TERMINATION_REQUESTED_I32:.*]] = llvm.call @talos_rt_v1_scheduler_termination_requested
// CHECK: llvm.trunc %[[TERMINATION_REQUESTED_I32]] : i32 to i1
// CHECK: llvm.call @talos_rt_v1_time_scan_scale
// CHECK: llvm.mlir.constant(8 : i32) : i32
// CHECK: llvm.call @talos_rt_v1_string_output_format
// CHECK: llvm.zext {{.*}} : i1 to i32
// CHECK: llvm.mlir.constant(16 : i32) : i32
// CHECK: llvm.call @talos_rt_v1_display
// CHECK: llvm.call @talos_rt_v1_file_readmem_token
// CHECK: llvm.call @talos_rt_v1_file_getc
// CHECK: llvm.call @talos_rt_v1_file_seek
// CHECK: llvm.call @talos_rt_v1_scheduler_program_exit(%arg0) : (!llvm.ptr) -> i32
// CHECK-NEXT: llvm.call @talos_rt_v1_gc_collect_pending(%arg0) : (!llvm.ptr) -> i32
// CHECK-NEXT: %[[OWNED:.*]] = llvm.call @talos_rt_v1_scheduler_program_owned(%arg0) : (!llvm.ptr) -> i32
// CHECK-NEXT: llvm.trunc %[[OWNED]] : i32 to i1
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_time(%arg0) : (!llvm.ptr) -> i64
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_cohort(%arg0) : (!llvm.ptr) -> i64
// CHECK: llvm.call @talos_rt_v1_string_output_fields(%arg0,
// CHECK: llvm.call @talos_rt_v1_time_format(%arg0,
// CHECK: llvm.call @talos_rt_v1_dump_open(%arg0,
// CHECK-NEXT: llvm.call @talos_rt_v1_dump_timescale(%arg0,
// CHECK: llvm.call @talos_rt_v1_dump_vars(%arg0,
// CHECK-NEXT: llvm.call @talos_rt_v1_dump_all(%arg0) : (!llvm.ptr) -> i32
// CHECK-NEXT: llvm.call @talos_rt_v1_dump_control(%arg0,
// CHECK-NEXT: llvm.call @talos_rt_v1_dump_limit(%arg0,
// CHECK-NEXT: llvm.call @talos_rt_v1_dump_flush(%arg0) : (!llvm.ptr) -> i32
// CHECK: llvm.call @talos_rt_v1_fragment_execute
// CHECK: llvm.load {{.*}} {alignment = 8 : i64} : !llvm.ptr -> !llvm.struct<(i32, i32, i32, i32, i64, i64)>
