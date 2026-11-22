//===- NativeRuntimePrototypeTest.cpp - Catalog prototypes ----------------===//
//
// Lowering declares each native runtime entry with the prototype of its row
// in NativeRuntimeEntries.def. Each row with a prototype in the public runtime
// headers or the runtime's private entry header is checked against it at
// compile time, so a row that disagrees with the C ABI fails the build and
// names its symbol.
//
//===----------------------------------------------------------------------===//

#include "lib/PrivateEntries.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Native/NativeRuntimeEntries.h"
#include "talos/Runtime/EvalNBAQueue.h"
#include "talos/Runtime/Runtime.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/Support/raw_ostream.h"

#include "gtest/gtest.h"

#include <cstddef>
#include <initializer_list>
#include <type_traits>

namespace {

using talos::NativeRuntimeEntry;
using namespace talos::native_runtime;

template <typename T> constexpr std::size_t byteSize() {
  if constexpr (std::is_void_v<T>)
    return 0;
  else
    return sizeof(T);
}

// Whether the C type `T` is passed as `type`: integers and enumerations by
// width, any pointer as Ptr.
template <typename T> constexpr bool passedAs(Type type) {
  constexpr bool integer =
      (std::is_integral_v<T> || std::is_enum_v<T>) && !std::is_same_v<T, bool>;
  switch (type) {
  case V:
    return std::is_void_v<T>;
  case I1:
    return std::is_same_v<T, bool>;
  case I8:
    return integer && byteSize<T>() == 1;
  case I16:
    return integer && byteSize<T>() == 2;
  case I32:
    return integer && byteSize<T>() == 4;
  case I64:
    return integer && byteSize<T>() == 8;
  case F32:
    return std::is_same_v<T, float>;
  case F64:
    return std::is_same_v<T, double>;
  case Ptr:
    return std::is_pointer_v<T>;
  }
  return false;
}

template <typename Function> struct Prototype;
template <typename Result, typename... Parameters>
struct Prototype<Result (*)(Parameters...)> {
  static constexpr bool matches(std::initializer_list<Type> signature) {
    if (signature.size() != sizeof...(Parameters) + 1)
      return false;
    const Type *type = signature.begin();
    bool matched = passedAs<Result>(*type++);
    ((matched = matched && passedAs<Parameters>(*type++)), ...);
    return matched;
  }
};
template <typename Result, typename... Parameters>
struct Prototype<Result (*)(Parameters...) noexcept>
    : Prototype<Result (*)(Parameters...)> {};

// The check can fail: in the result's or a parameter's width, its kind, or
// the number of parameters.
static_assert(Prototype<int32_t (*)(void *)>::matches({I32, Ptr}));
static_assert(!Prototype<int32_t (*)(void *)>::matches({I64, Ptr}));
static_assert(!Prototype<int32_t (*)(uint16_t)>::matches({I32, I32}));
static_assert(!Prototype<int32_t (*)(void *)>::matches({I32}));
static_assert(!Prototype<int32_t (*)(void *)>::matches({I32, Ptr, Ptr}));
static_assert(!Prototype<int32_t (*)(int64_t)>::matches({I32, Ptr}));
static_assert(!Prototype<void *(*)()>::matches({I64}));
static_assert(!Prototype<bool (*)()>::matches({I8}));
static_assert(!Prototype<float (*)()>::matches({F64}));
static_assert(!Prototype<void (*)()>::matches({I32}));

#define SIG(...) {__VA_ARGS__}
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  static_assert(Prototype<decltype(&::symbol)>::matches(signature),            \
                #symbol " disagrees with its C prototype");
#define TALOS_NATIVE_RUNTIME_PROTOTYPED_ONLY
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
#undef TALOS_NATIVE_RUNTIME_PROTOTYPED_ONLY
#undef SIG

// Calls name their callee by symbol: every row's symbol finds its row.
TEST(NativeRuntimeEntries, SymbolsFindTheirRows) {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  EXPECT_EQ(talos::getNativeRuntimeEntry(#symbol), NativeRuntimeEntry::Enum);  \
  EXPECT_EQ(talos::getNativeRuntimeSymbol(NativeRuntimeEntry::Enum).str(),     \
            #symbol);
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
  EXPECT_FALSE(talos::getNativeRuntimeEntry("talos_rt_v1_no_such_entry"));
  EXPECT_FALSE(talos::getNativeRuntimeEntry(""));
}

// Every entry's native.runtime_entry attribute parses back from its printed
// form: the printer drops the symbol's talos_rt_v1_ (else talos_rt_) prefix,
// and the parser tries the talos_rt_v1_ symbol first.
TEST(NativeRuntimeEntries, AttributesRoundTrip) {
  mlir::MLIRContext context;
  context.loadDialect<talos::native::NativeDialect>();
  static constexpr NativeRuntimeEntry entries[] = {
#define TALOS_NATIVE_RUNTIME(Enum, symbol, signature, effects)                 \
  NativeRuntimeEntry::Enum,
#include "talos/Dialect/Native/NativeRuntimeEntries.def"
  };
  for (NativeRuntimeEntry entry : entries) {
    auto attribute = talos::native::RuntimeEntryAttr::get(&context, entry);
    std::string text;
    llvm::raw_string_ostream(text) << attribute;
    EXPECT_EQ(mlir::parseAttribute(text, &context), attribute) << text;
  }
}

} // namespace
