//===- Options.cpp - Talos coverage tool option table ----------------===//

#include "Options.h"

#include "llvm/Option/Option.h"

using namespace talos::coverage::options;
using namespace llvm::opt;

#define OPTTABLE_STR_TABLE_CODE
#include "Options.inc"
#undef OPTTABLE_STR_TABLE_CODE

#define OPTTABLE_PREFIXES_TABLE_CODE
#include "Options.inc"
#undef OPTTABLE_PREFIXES_TABLE_CODE

#define OPTTABLE_PREFIXES_UNION_CODE
#include "Options.inc"
#undef OPTTABLE_PREFIXES_UNION_CODE

#define OPTTABLE_SUBCOMMANDS_CODE
#include "Options.inc"
#undef OPTTABLE_SUBCOMMANDS_CODE

#define OPTTABLE_SUBCOMMAND_IDS_TABLE_CODE
#include "Options.inc"
#undef OPTTABLE_SUBCOMMAND_IDS_TABLE_CODE

static constexpr OptTable::Info optionInfoTable[] = {
#define OPTION(...) LLVM_CONSTRUCT_OPT_INFO(__VA_ARGS__),
#include "Options.inc"
#undef OPTION
};

namespace {

class CoverageOptTable : public PrecomputedOptTable {
public:
  CoverageOptTable()
      : PrecomputedOptTable(OptionStrTable, OptionPrefixesTable,
                            optionInfoTable, OptionPrefixesUnion, false,
                            OptionSubCommands, OptionSubCommandIDsTable) {}
};

} // namespace

const OptTable &talos::coverage::getCoverageOptTable() {
  static CoverageOptTable table;
  return table;
}
