#ifndef TALOS_UPF_DESIGNQUERY_H
#define TALOS_UPF_DESIGNQUERY_H

#ifdef TALOS_ENABLE_UPF
#include "SupplyNetwork.h"
#include "mlir/IR/BuiltinOps.h"
#include <map>
#include <set>
#include <string>
#include <tcl.h>
#include <vector>

namespace talos {
class DesignAttributes;
/// Compiler-only queries over declared HDL objects. Keep source hierarchy
/// components separate: an escaped HDL identifier can contain '.' or '/'.
class DesignQuery {
public:
  explicit DesignQuery(mlir::ModuleOp module);
  std::string resolve(llvm::StringRef name, llvm::StringRef scope,
                      llvm::StringRef top) const;
  std::string rooted(llvm::StringRef scope, llvm::StringRef top) const;
  bool isScope(llvm::StringRef path) const;
  std::string parent(llvm::StringRef path) const;
  bool isTop(llvm::StringRef path) const;
  mlir::Operation *process(llvm::StringRef path) const;
  mlir::Operation *processBody(llvm::StringRef path) const;
  bool isNamedBlock(llvm::StringRef path) const;
  bool isPort(llvm::StringRef path) const;
  const std::map<std::string, mlir::Operation *> &portDeclarations() const {
    return ports;
  }
  int find(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
           llvm::StringRef scope, llvm::StringRef top,
           const SupplyPorts &supplyPorts, DesignAttributes &attributes) const;

private:
  struct Path {
    std::vector<std::string> names;
    std::vector<size_t> escapedLength;
    static Path fromHDL(llvm::StringRef name);
    std::vector<std::string> keys() const;
    std::string upf(size_t start = 0) const;
  };
  enum class Kind { Instance, Port, Net, Process };
  struct Object {
    Path path;
    mlir::Operation *declaration;
    Kind kind;
    std::string model;
  };
  std::map<std::vector<std::string>, std::string> names;
  std::map<std::string, Path> scopes;
  std::map<std::string, mlir::Operation *> processes;
  std::set<std::string> namedBlocks;
  std::map<std::string, mlir::Operation *> ports;
  std::vector<Object> objects;
};
} // namespace talos
#endif
#endif
