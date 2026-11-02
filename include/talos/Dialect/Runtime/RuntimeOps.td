//===- RuntimeOps.td - Typed runtime ABI operations -----------*- tablegen -*-===//

#ifndef TALOS_DIALECT_RUNTIME_RUNTIMEOPS_TD
#define TALOS_DIALECT_RUNTIME_RUNTIMEOPS_TD

include "talos/Dialect/Runtime/RuntimeAttrs.td"
include "talos/Dialect/Runtime/RuntimeDialect.td"
include "talos/Dialect/Runtime/RuntimeTypes.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def RTRuntimeResource : Resource<"::talos::runtime::RuntimeResource">;
def RTIOResource : Resource<"::talos::runtime::IOResource">;

class RTOp<string mnemonic, list<Trait> traits = []>
    : Op<TalosRuntimeDialect, mnemonic, traits> {
  let assemblyFormat = "operands attr-dict `:` functional-type(operands, results)";
}

// Compiler materializers. These operations make all target-layout-sensitive
// records and storage explicit before the LLVM boundary.
def RTBytesConstantOp : RTOp<"bytes.constant", [Pure, ConstantLike]> {
  let summary = "borrow an immutable byte-string constant";
  let description = [{
    Produces a borrowed byte span whose length is the exact string-attribute
    length, including embedded zero bytes. It has no ownership to release.
  }];
  let arguments = (ins StrAttr:$value);
  let results = (outs RTByteSpanType:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

def RTScratchOp : RTOp<"bytes.scratch", [MemoryEffects<[MemAlloc]>]> {
  let summary = "allocate mutable scratch bytes for the current activation";
  let description = [{
    Allocates `size` nonnegative bytes. Consumers remain in the same block
    and are limited to file reads, readmem-token reads, and packed-byte
    conversion. Native lowering gives this storage automatic lifetime.
  }];
  let arguments = (ins I64Attr:$size);
  let results = (outs RTMutableByteSpanType:$result);
  let assemblyFormat = "$size attr-dict";
  let hasVerifier = 1;
}

def RTBytesSizeOp : RTOp<"bytes.size", [Pure]> {
  let summary = "read the length of a byte span or owned buffer";
  let arguments = (ins AnyType:$bytes);
  let results = (outs I64:$size);
  let assemblyFormat = "$bytes attr-dict `:` type($bytes)";
  let hasVerifier = 1;
}

def RTPackedFromBytesOp : RTOp<"bytes.to_packed", [MemoryEffects<[MemRead]>]> {
  let summary = "copy bytes into a packed two-state integer";
  let description = [{
    Copies up to `count` bytes, bounded by the source length and destination
    capacity, and zero-fills unused positions. By default the first byte is
    the most significant byte of the copied sequence, aligned to the low end
    of the result. `high_alignment` aligns it to the destination byte capacity
    instead. `least_significant_byte_first` reverses byte significance and
    cannot be combined with high alignment.
  }];
  let arguments = (ins AnyType:$bytes, I64:$count,
                       BoolAttr:$high_alignment,
                       DefaultValuedAttr<BoolAttr, "false">:
                           $least_significant_byte_first);
  let results = (outs AnyInteger:$result);
  let hasVerifier = 1;
}

def RTArgumentEmptyOp : RTOp<"argument.empty", [Pure]> {
  let summary = "materialize an empty formatting argument";
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "attr-dict";
  let hasVerifier = 1;
}

def RTArgumentPackedOp : RTOp<"argument.packed", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package packed value and unknown planes for formatting";
  let arguments = (ins AnyInteger:$value, Optional<AnyInteger>:$unknown,
                       BoolAttr:$is_signed);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentEnumOp : RTOp<"argument.enum", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a packed enum value and its name for formatting";
  let arguments = (ins AnyInteger:$value, Optional<AnyInteger>:$unknown,
                       I64:$name, BoolAttr:$is_signed);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentNetOp : RTOp<"argument.net", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a packed net value and its handle for formatting";
  let arguments = (ins AnyInteger:$value, Optional<AnyInteger>:$unknown,
                       I64:$handle, BoolAttr:$is_signed);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentRawAggregateOp
    : RTOp<"argument.raw_aggregate", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package aggregate assignment-pattern and raw-byte strings";
  let description = [{
    The three operands are managed strings holding an assignment-pattern
    rendering and the independently leaf-padded two-state and four-state raw
    encodings of the aggregate. They support `%p`, `%u`, and `%z` output
    without reconstructing the source aggregate layout at the ABI boundary.
  }];
  let arguments = (ins I64:$pattern, I64:$two_state, I64:$four_state);
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "$pattern `,` $two_state `,` $four_state attr-dict";
  let hasVerifier = 1;
}

def RTArgumentRealOp : RTOp<"argument.real", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a real or realtime formatting argument";
  let arguments = (ins F64:$value,
                       DefaultValuedAttr<BoolAttr, "false">:$is_time);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentBytesOp : RTOp<"argument.bytes", [Pure]> {
  let summary = "borrow byte-string data as a formatting argument";
  let arguments = (ins RTByteSpanType:$value,
                       BoolAttr:$is_format_string,
                       DefaultValuedAttr<BoolAttr, "false">:$designated_format);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentManagedStringOp
    : RTOp<"argument.managed_string", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a managed string as a formatting argument";
  let arguments = (ins I64:$value, BoolAttr:$is_format_string,
                       DefaultValuedAttr<BoolAttr, "false">:$designated_format);
  let results = (outs RTArgumentType:$result);
  let hasVerifier = 1;
}

def RTArgumentManagedContainerOp
    : RTOp<"argument.managed_container", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a managed container for formatting";
  let arguments = (ins I64:$value);
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTArgumentManagedObjectOp
    : RTOp<"argument.managed_object", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a managed class object for formatting";
  let arguments = (ins I64:$value);
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTArgumentVirtualInterfaceOp
    : RTOp<"argument.virtual_interface", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a virtual-interface handle for formatting";
  let arguments = (ins I64:$value);
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTArgumentProcessOp
    : RTOp<"argument.process", [MemoryEffects<[MemAlloc]>]> {
  let summary = "package a process handle for formatting";
  let arguments = (ins I64:$value);
  let results = (outs RTArgumentType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTArgumentArrayOp : RTOp<"argument.array", [MemoryEffects<[MemAlloc]>]> {
  let summary = "materialize an ordered array of formatting arguments";
  let description = [{
    Collects logical formatting arguments in source order. The materialized
    array is local to its producer block and is consumed by formatting or
    display calls in that block.
  }];
  let arguments = (ins Variadic<RTArgumentType>:$arguments);
  let results = (outs RTArgumentArrayType:$result);
  let assemblyFormat = "`(` $arguments `)` attr-dict";
  let hasVerifier = 1;
}

def RTFormatEnvironmentOp : RTOp<"format.environment", [
  MemoryEffects<[MemAlloc]>
]> {
  let summary = "materialize scope and time metadata for formatting";
  let arguments = (ins DefaultValuedAttr<StrAttr, "\"\"">:$scope,
                       DefaultValuedAttr<StrAttr, "\"\"">:$library_cell,
                       DefaultValuedAttr<I32Attr, "0">:$time_width,
                       DefaultValuedAttr<I32Attr, "0">:$time_precision,
                       DefaultValuedAttr<StrAttr, "\"\"">:$time_suffix,
                       DefaultValuedAttr<I64Attr, "1">:$time_multiplier);
  let results = (outs RTFormatEnvironmentType:$result);
  let assemblyFormat = "attr-dict";
  let hasVerifier = 1;
}

def RTFileDescriptorFromBitsOp : RTOp<"file_descriptor.from_bits", [Pure]> {
  let summary = "interpret raw bits as a runtime file descriptor";
  let arguments = (ins I32:$value);
  let results = (outs RTFileDescriptorType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTFileDescriptorToBitsOp : RTOp<"file_descriptor.to_bits", [Pure]> {
  let summary = "expose the raw bits of a runtime file descriptor";
  let arguments = (ins RTFileDescriptorType:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTStatusIsOp : RTOp<"status.is", [Pure]> {
  let summary = "compare a runtime status with a named status code";
  let arguments = (ins RTStatusType:$status, RTStatusCodeAttr:$value);
  let results = (outs I1:$result);
  let assemblyFormat = "$status `,` $value attr-dict";
}

def RTStatusFromBitsOp : RTOp<"status.from_bits", [Pure]> {
  let summary = "interpret raw bits as a runtime status";
  let arguments = (ins I32:$value);
  let results = (outs RTStatusType:$result);
  let assemblyFormat = "$value attr-dict";
}

def RTStatusToBitsOp : RTOp<"status.to_bits", [Pure]> {
  let summary = "expose the raw bits of a runtime status";
  let arguments = (ins RTStatusType:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

// Context, errors, and owned buffers.
def RTContextCreateOp : RTOp<"context.create", [
  MemoryEffects<[MemAlloc<RTRuntimeResource>]>
]> {
  let summary = "create an owned runtime context";
  let results = (outs RTStatusType:$status, RTContextType:$context);
}

def RTContextDestroyOp : RTOp<"context.destroy", [
  MemoryEffects<[MemFree<RTRuntimeResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "destroy a runtime context and its resources";
  let arguments = (ins RTContextType:$context);
}

def RTStatusStringOp : RTOp<"status.string", [Pure]> {
  let summary = "borrow the static diagnostic text for a runtime status";
  let arguments = (ins RTStatusType:$status);
  let results = (outs RTCStringType:$string);
}

def RTBufferReleaseOp : RTOp<"buffer.release", [
  MemoryEffects<[MemFree<RTRuntimeResource>, MemFree]>
]> {
  let summary = "release an owned runtime buffer";
  let description = [{
    Consumes a buffer produced directly by `runtime.last_error`,
    `runtime.format`, `runtime.file.getline`, or `runtime.file.error`.
    Each owned buffer has exactly one release, at most one size query, and
    at most one packed read. All uses remain in the producer's block, with
    queries and reads preceding the release.
  }];
  let arguments = (ins RTBufferType:$buffer);
  let hasVerifier = 1;
}

def RTLastErrorOp : RTOp<"last_error", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemAlloc<RTRuntimeResource>, MemAlloc]>
]> {
  let summary = "copy the last runtime error into an owned buffer";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status, RTBufferType:$message);
  let hasVerifier = 1;
}

def RTFinishOp : RTOp<"finish", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>]>
]> {
  let summary = "request simulation completion with the specified verbosity";
  let arguments = (ins RTContextType:$context, I32:$verbosity);
  let results = (outs RTStatusType:$status);
}

def RTProgramExitOp : RTOp<"program.exit", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>]>
]> {
  let summary = "request termination of the current program instance";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

def RTStopOp : RTOp<"stop", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>]>
]> {
  let summary = "request a simulation stop with the specified verbosity";
  let arguments = (ins RTContextType:$context, I32:$verbosity);
  let results = (outs RTStatusType:$status);
}

def RTFatalOp : RTOp<"fatal", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>]>
]> {
  let summary = "request fatal simulation termination";
  let arguments = (ins RTContextType:$context, I32:$verbosity);
  let results = (outs RTStatusType:$status);
}

def RTErrorOp : RTOp<"error", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>]>
]> {
  let summary = "record a simulation error";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

// Delimit sim.publication.batch_begin/end. Transition publication reaches the
// runtime through ordinary memory, so both are full barriers here.
def RTPublicationBatchBeginOp : RTOp<"publication.batch_begin", [
  MemoryEffects<[MemRead, MemWrite, MemRead<RTRuntimeResource>,
                 MemWrite<RTRuntimeResource>, MemRead<RTIOResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "begin an atomic batch of transition publications";
  let description = [{
    Delays delivery of update events while a generated statement publishes
    its complete result. The matching `runtime.publication.batch_end`
    delivers the held events. Both operations are memory and scheduling
    barriers, including for publications performed through ordinary memory.
  }];
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

def RTPublicationBatchEndOp : RTOp<"publication.batch_end", [
  MemoryEffects<[MemRead, MemWrite, MemRead<RTRuntimeResource>,
                 MemWrite<RTRuntimeResource>, MemRead<RTIOResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "complete a batch and publish its accumulated effects";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

// Reclaim deferred managed-heap pressure at a designated collection point.
def RTGCCollectOp : RTOp<"gc.collect", [
  MemoryEffects<[MemRead, MemWrite, MemRead<RTRuntimeResource>,
                 MemWrite<RTRuntimeResource>]>
]> {
  let summary = "collect deferred managed-heap allocation pressure";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

def RTProgramOwnedOp : RTOp<"program.owned", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "test whether the current process belongs to a program";
  let arguments = (ins RTContextType:$context);
  let results = (outs I1:$result);
}

def RTTerminationRequestedOp : RTOp<"termination.requested", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "test whether simulation termination was requested";
  let arguments = (ins RTContextType:$context);
  let results = (outs I1:$result);
}

def RTSchedulerTimeOp : RTOp<"scheduler.time", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "read scheduler time in design-precision ticks";
  let arguments = (ins RTContextType:$context);
  let results = (outs I64:$result);
}
def RTSchedulerCohortOp : RTOp<"scheduler.cohort", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "read the current ordered scheduler cohort token";
  let arguments = (ins RTContextType:$context);
  let results = (outs I64:$result);
}

// Formatting and display.
def RTFormatOp : RTOp<"format", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemAlloc<RTRuntimeResource>, MemRead, MemAlloc]>
]> {
  let summary = "format arguments into an owned byte buffer";
  let description = [{
    Formats the complete ordered argument array using the explicit format
    bytes and call-site environment. The returned buffer must be released in
    the same block with `runtime.buffer.release` after any size or packed read.
  }];
  let arguments = (ins RTContextType:$context, RTByteSpanType:$format,
                       RTArgumentArrayType:$arguments,
                       RTFormatEnvironmentType:$environment);
  let results = (outs RTStatusType:$status, RTBufferType:$buffer);
  let hasVerifier = 1;
}

def RTStringOutputFormatOp : RTOp<"string_output_format", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemAlloc<RTRuntimeResource>, MemRead, MemAlloc]>
]> {
  let summary = "format output items into a managed string";
  let arguments = (ins RTContextType:$context,
                       RTArgumentArrayType:$items,
                       RTFormatEnvironmentType:$environment,
                       RTRadixAttr:$default_radix);
  let results = (outs RTStatusType:$status, AnyType:$string);
}

def RTDisplayOp : RTOp<"display", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "format and write output items to a file descriptor";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       I1:$append_newline, RTArgumentArrayType:$items,
                       RTFormatEnvironmentType:$environment,
                       RTRadixAttr:$default_radix);
  let results = (outs RTStatusType:$status);
}

def RTTimeFormatOp : RTOp<"time.format", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "set the design-wide time formatting parameters";
  let arguments = (ins RTContextType:$context, I32:$units,
                       I32:$fraction_digits, RTByteSpanType:$suffix,
                       I32:$width);
  let results = (outs RTStatusType:$status);
}

def RTTimeScanScaleOp : RTOp<"time.scan_scale", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "convert a scanned time using the active time format";
  let arguments = (ins RTContextType:$context, F64:$input,
                       I64:$time_multiplier, I32:$time_precision);
  let results = (outs F64:$result);
}

// Waveform services. Collection itself is a scheduler-driven difference over
// the canonical state planes; these calls only configure and gate it.
def RTDumpOpenOp : RTOp<"dump.open", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "open the waveform output path";
  let arguments = (ins RTContextType:$context, RTByteSpanType:$path);
  let results = (outs RTStatusType:$status);
}

def RTDumpTimescaleOp : RTOp<"dump.timescale", [
  MemoryEffects<[MemWrite<RTRuntimeResource>]>
]> {
  let summary = "set the waveform timescale exponent";
  let arguments = (ins RTContextType:$context, I32:$exponent);
  let results = (outs RTStatusType:$status);
}

def RTDumpVarsOp : RTOp<"dump.vars", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "select a scope and hierarchy depth for waveform collection";
  let arguments = (ins RTContextType:$context, I64:$levels,
                       RTByteSpanType:$scope);
  let results = (outs RTStatusType:$status);
}

def RTDumpAllOp : RTOp<"dump.all", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "dump all selected waveform values";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

def RTDumpControlOp : RTOp<"dump.control", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "enable or disable waveform collection";
  let arguments = (ins RTContextType:$context, I32:$enabled);
  let results = (outs RTStatusType:$status);
}

def RTDumpLimitOp : RTOp<"dump.limit", [
  MemoryEffects<[MemWrite<RTRuntimeResource>]>
]> {
  let summary = "set the waveform output byte limit";
  let arguments = (ins RTContextType:$context, I64:$bytes);
  let results = (outs RTStatusType:$status);
}

def RTDumpFlushOp : RTOp<"dump.flush", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "flush waveform output";
  let arguments = (ins RTContextType:$context);
  let results = (outs RTStatusType:$status);
}

// File services.
def RTFileOpenMCDOp : RTOp<"file.open_mcd", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "open a file as a multichannel descriptor";
  let arguments = (ins RTContextType:$context, RTByteSpanType:$path);
  let results = (outs RTStatusType:$status, RTFileDescriptorType:$descriptor);
}

def RTFileOpenOp : RTOp<"file.open", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "open a file with an explicit mode";
  let arguments = (ins RTContextType:$context, RTByteSpanType:$path,
                       RTByteSpanType:$mode);
  let results = (outs RTStatusType:$status, RTFileDescriptorType:$descriptor);
}

def RTFileCloseOp : RTOp<"file.close", [
  MemoryEffects<[MemWrite<RTRuntimeResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "close the streams selected by a file descriptor";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status);
}

def RTFileFlushOp : RTOp<"file.flush", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "flush the streams selected by a file descriptor";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status);
}

def RTFileWriteOp : RTOp<"file.write", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>, MemRead]>
]> {
  let summary = "write bytes and return the number written";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       RTByteSpanType:$data);
  let results = (outs RTStatusType:$status, I64:$written);
}

def RTFileReadOp : RTOp<"file.read", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>, MemWrite]>
]> {
  let summary = "read bytes into mutable storage and return the count";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       RTMutableByteSpanType:$data);
  let results = (outs RTStatusType:$status, I64:$read);
}

def RTFileReadMemTokenOp : RTOp<"file.readmem_token", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>, MemWrite]>
]> {
  let summary = "read one IEEE $readmem token from a file";
  let description = [{
    Reads a binary or hexadecimal memory-file token. `kind` distinguishes
    end of file (0), data (1), and an address directive (2). Data is decoded
    into the destination value and unknown byte spans at `bitWidth` bits;
    an address directive returns its location in `address`.
  }];
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       I32:$radix, I64:$bitWidth,
                       RTMutableByteSpanType:$value,
                       RTMutableByteSpanType:$unknown);
  let results = (outs RTStatusType:$status, I32:$kind, I64:$address);
}

def RTFileGetcOp : RTOp<"file.getc", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>]>
]> {
  let summary = "read one byte from a file";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status, I8:$byte);
}

def RTFileUngetcOp : RTOp<"file.ungetc", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "push one byte back onto a file stream";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       I8:$byte);
  let results = (outs RTStatusType:$status);
}

def RTFileGetlineOp : RTOp<"file.getline", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>,
                 MemAlloc<RTRuntimeResource>, MemAlloc]>
]> {
  let summary = "read a bounded line into an owned buffer";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       I64:$max_bytes);
  let results = (outs RTStatusType:$status, RTBufferType:$line);
  let hasVerifier = 1;
}

def RTFileEofOp : RTOp<"file.eof", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>]>
]> {
  let summary = "query the end-of-file indicator";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status, I32:$is_eof);
}

def RTFileErrorOp : RTOp<"file.error", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemAlloc<RTRuntimeResource>, MemAlloc]>
]> {
  let summary = "query a file error code and owned diagnostic message";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status, I32:$error_code,
                      RTBufferType:$message);
  let hasVerifier = 1;
}

def RTFileSeekOp : RTOp<"file.seek", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "seek relative to a specified file origin";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor,
                       I64:$offset, I32:$origin);
  let results = (outs RTStatusType:$status);
}

def RTFileTellOp : RTOp<"file.tell", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>]>
]> {
  let summary = "read the current file position";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status, I64:$offset);
}

def RTFileRewindOp : RTOp<"file.rewind", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemWrite<RTIOResource>]>
]> {
  let summary = "rewind a file and clear its error indicators";
  let arguments = (ins RTContextType:$context, RTFileDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status);
}

// Uniform fragment dispatch. Lifecycle and driver construction deliberately
// remain outside bytecode-callable services.
def RTFragmentExecuteOp : RTOp<"fragment.execute", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>, MemRead,
                 MemWrite]>
]> {
  let summary = "execute one native or bytecode fragment continuation";
  let description = [{
    Dispatches the immutable fragment descriptor using the supplied context,
    mutable canonical frame, and continuation index. Native and bytecode
    implementations share this ABI and return a runtime status and a fragment
    action describing continuation, suspension, or termination.
  }];
  let arguments = (ins RTFragmentDescriptorType:$descriptor,
                       RTContextType:$context, RTMutableByteSpanType:$frame,
                       I32:$continuation);
  let results = (outs RTStatusType:$status, RTFragmentActionType:$action);
}

def RTBytecodeExecuteBoundedOp : RTOp<"bytecode.execute_bounded", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>, MemRead,
                 MemWrite]>
]> {
  let summary = "execute bytecode with an instruction budget";
  let description = [{
    Executes a bytecode fragment with the same inputs and action result as
    `runtime.fragment.execute`. A nonzero `instruction_limit` bounds this
    invocation and returns the step-limit status when exhausted; zero leaves
    the invocation unbounded.
  }];
  let arguments = (ins RTFragmentDescriptorType:$descriptor,
                       RTContextType:$context, RTMutableByteSpanType:$frame,
                       I32:$continuation, I64:$instruction_limit);
  let results = (outs RTStatusType:$status, RTFragmentActionType:$action);
}

// Runtime-owned suspendable process instances. Creation performs the sole
// lifetime allocation; frame returns only the canonical prefix, while execute
// selects an available native or bytecode tier without moving that prefix.
def RTProcessInstanceCreateOp : RTOp<"process.instance.create", [
  MemoryEffects<[MemRead, MemAlloc<RTRuntimeResource>, MemAlloc]>
]> {
  let summary = "allocate a process instance and its canonical frame";
  let description = [{
    Creates the runtime-owned instance, canonical frame, and shared scratch
    tail in one lifetime allocation. The scratch tail can serve native or
    bytecode execution without moving or copying the canonical frame.
    The instance is released with `runtime.process.instance.destroy`.
  }];
  let arguments = (ins RTProcessDescriptorType:$descriptor);
  let results = (outs RTStatusType:$status, RTProcessInstanceType:$instance);
}

def RTProcessInstanceFrameOp : RTOp<"process.instance.frame", [
  MemoryEffects<[MemRead<RTRuntimeResource>]>
]> {
  let summary = "borrow the canonical frame of a process instance";
  let description = [{
    Returns a mutable byte span covering only the canonical frame prefix.
    The span borrows storage owned by the process instance; it excludes the
    shared scratch tail and must not outlive the instance.
  }];
  let arguments = (ins RTProcessInstanceType:$instance);
  let results = (outs RTStatusType:$status, RTMutableByteSpanType:$frame);
}

def RTProcessInstanceExecuteOp : RTOp<"process.instance.execute", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemRead<RTIOResource>, MemWrite<RTIOResource>, MemRead,
                 MemWrite]>
]> {
  let summary = "resume a process instance in an available execution tier";
  let description = [{
    Resumes the instance at its saved continuation using the requested native
    or bytecode tier when available. The canonical frame retains its address
    across tier selection. The returned action describes the next continuation,
    suspension, or termination.
  }];
  let arguments = (ins RTProcessInstanceType:$instance,
                       RTContextType:$context, I32:$requested_tier);
  let results = (outs RTStatusType:$status, RTFragmentActionType:$action);
}

def RTProcessInstanceDestroyOp : RTOp<"process.instance.destroy", [
  MemoryEffects<[MemRead<RTRuntimeResource>, MemWrite<RTRuntimeResource>,
                 MemFree<RTRuntimeResource>, MemFree]>
]> {
  let summary = "destroy a process instance and release its allocation";
  let arguments = (ins RTProcessInstanceType:$instance);
  let results = (outs RTStatusType:$status);
}

#endif // TALOS_DIALECT_RUNTIME_RUNTIMEOPS_TD
