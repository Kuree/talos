//===- FallbackReport.cpp - Structured tier-1 fallback records ------------===//

#include "talos/Dialect/Native/FallbackReport.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "llvm/Support/JSON.h"
#include <mutex>

using namespace mlir;

namespace talos::native {
namespace {
/// Never destroyed: the driver detaches its report file from a static
/// destructor, and destruction order across translation units is unspecified
/// (on macOS, locking a destroyed mutex throws).
std::mutex &getReportMutex() {
  static std::mutex *mutex = new std::mutex;
  return *mutex;
}
llvm::raw_ostream *reportStream = nullptr;

/// The first file position a location names, as "file:line:column".
std::string formatLocation(Location location) {
  std::string result;
  location->walk([&](Location nested) {
    if (auto file = dyn_cast<FileLineColLoc>(nested)) {
      result = (file.getFilename().getValue() + ":" + Twine(file.getLine()) +
                ":" + Twine(file.getColumn()))
                   .str();
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  return result;
}
} // namespace

bool isFallbackReportEnabled(ModuleOp module) {
  return module && has<FallbackReport>(module);
}

void reportFallback(ModuleOp module, const FallbackRecord &record) {
  if (!isFallbackReportEnabled(module))
    return;
  llvm::json::Object object{{"kind", record.kind},
                            {"reason", record.reason}};
  if (!record.owner.empty())
    object["owner"] = record.owner;
  if (record.location)
    if (std::string location = formatLocation(*record.location);
        !location.empty())
      object["loc"] = std::move(location);
  if (record.blocker)
    if (std::string blocker = formatLocation(*record.blocker);
        !blocker.empty())
      object["blocker"] = std::move(blocker);
  if (!record.detail.empty())
    object["detail"] = record.detail;
  std::string line;
  llvm::raw_string_ostream os(line);
  os << llvm::json::Value(std::move(object)) << '\n';
  std::lock_guard<std::mutex> lock(getReportMutex());
  // A report file holds plain JSON lines; stderr tags each line so it reads
  // among other diagnostics.
  if (reportStream) {
    *reportStream << line;
    reportStream->flush();
    return;
  }
  llvm::errs() << "talos fallback: " << line;
  llvm::errs().flush();
}

void setFallbackReportStream(llvm::raw_ostream *stream) {
  std::lock_guard<std::mutex> lock(getReportMutex());
  reportStream = stream;
}

} // namespace talos::native
