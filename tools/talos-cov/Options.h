//===- Options.h - Talos coverage tool options --------------*- C++ -*-===//

#ifndef TALOS_TOOLS_COV_OPTIONS_H
#define TALOS_TOOLS_COV_OPTIONS_H

#include "llvm/Option/OptTable.h"

namespace talos::coverage {
namespace options {

enum ID {
  OPT_INVALID = 0,
#define OPTION(...) LLVM_MAKE_OPT_ID(__VA_ARGS__),
#include "Options.inc"
#undef OPTION
};

} // namespace options

const llvm::opt::OptTable &getCoverageOptTable();

} // namespace talos::coverage

#endif // TALOS_TOOLS_COV_OPTIONS_H
