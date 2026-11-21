//===- NativeRuntimeEntries.cpp - Native runtime entry effects ------------===//

#include "NativeRuntimeEntries.h"

#include "llvm/ADT/StringSwitch.h"

namespace talos::detail {
using namespace native_runtime;

std::optional<NativeRuntimeEntry>
getNativeRuntimeEntry(llvm::StringRef callee) {
  return llvm::StringSwitch<std::optional<NativeRuntimeEntry>>(callee)
#define TALOS_NATIVE_RUNTIME(Enum, symbol, effects)                            \
  .Case(#symbol, NativeRuntimeEntry::Enum)
#include "NativeRuntimeEntries.def"
      .Default(std::nullopt);
}

llvm::StringRef getNativeRuntimeSymbol(NativeRuntimeEntry entry) {
  switch (entry) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, effects)                            \
  case NativeRuntimeEntry::Enum:                                               \
    return #symbol;
#include "NativeRuntimeEntries.def"
  }
  return {};
}

uint32_t getNativeRuntimeEffects(NativeRuntimeEntry entry) {
  switch (entry) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, effects)                            \
  case NativeRuntimeEntry::Enum:                                               \
    return effects;
#include "NativeRuntimeEntries.def"
  }
  return None;
}

bool hasNativeRuntimeEffect(llvm::StringRef callee, Effect effect) {
  std::optional<NativeRuntimeEntry> entry = getNativeRuntimeEntry(callee);
  return entry && (getNativeRuntimeEffects(*entry) & effect) == effect;
}

} // namespace talos::detail
