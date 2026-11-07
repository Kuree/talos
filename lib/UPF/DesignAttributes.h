#ifndef TALOS_UPF_DESIGNATTRIBUTES_H
#define TALOS_UPF_DESIGNATTRIBUTES_H
#ifdef TALOS_ENABLE_UPF
#include "DesignQuery.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/SmallVector.h"
#include <map>
#include <memory>
#include <optional>
#include <tuple>

namespace talos {
class PortAttributes;
// One property registry for immediate Tcl queries and final compiler metadata.
// Keep every explicit source: precedence is per property, never source order.
class DesignAttributes {
public:
  struct Source {
    mlir::Attribute value;
    mlir::Location location;
    unsigned precedence;
    std::string model, scope, top;
  };
  using Properties = std::map<std::string, llvm::SmallVector<Source, 1>>;
  DesignAttributes(mlir::ModuleOp module,
                   const std::map<std::string, mlir::Operation *> &objects,
                   const DesignQuery &queries);
  ~DesignAttributes();
  mlir::LogicalResult initialize();
  int set(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
          llvm::StringRef scope, llvm::StringRef top, mlir::Location location);
  int setPorts(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
               llvm::StringRef scope, llvm::StringRef top,
               mlir::Location location,
               llvm::function_ref<mlir::FailureOr<std::string>(llvm::StringRef)>
                   resolveSupply);
  mlir::Attribute get(llvm::StringRef path, llvm::StringRef property) const;
  mlir::DictionaryAttr get(llvm::StringRef path) const;
  bool hardMacro(llvm::StringRef path) const;
  bool softMacro(llvm::StringRef path) const;
  bool leaf(llvm::StringRef path) const;
  bool hasMacros() const;
  bool hasPortAttributes() const;
  bool insideLeaf(llvm::StringRef path, llvm::StringRef context,
                  bool includeSelf = false, bool hardOnly = false);
  bool exhausted() const { return exceeded; }
  std::string instance(llvm::StringRef path) const;
  struct Reference {
    std::string path, scope, top;
    mlir::Location location;
    bool includeSelf;
    bool localModel = false;
  };
  std::string boundary(llvm::StringRef path, llvm::StringRef top,
                       bool includeSelf = false, bool localModel = false);
  bool record(Reference reference);
  mlir::LogicalResult emit(mlir::OpBuilder &builder);

private:
  struct Model {
    mlir::Operation *declaration;
    std::string name;
    llvm::SmallVector<std::string> instances;
  };
  mlir::ModuleOp module;
  const std::map<std::string, mlir::Operation *> &objects;
  const DesignQuery &queries;
  std::unique_ptr<PortAttributes> ports;
  std::map<std::string, Model> models;
  std::map<std::string, Properties> properties;
  std::map<std::string, std::string> instanceModels;
  mutable std::map<std::string, std::string> parents;
  struct ModelSpecification {
    std::string model, scope, top;
    mlir::DictionaryAttr values;
    mlir::Location location;
  };
  llvm::SmallVector<ModelSpecification> modelSpecifications;
  llvm::SmallVector<Reference> references;
  size_t work = 0;
  bool exceeded = false;
  std::map<std::tuple<std::string, std::string, bool, bool>, bool> leafCache;
  bool charge(size_t count = 1);
  bool isInstance(llvm::StringRef path) const;
  std::string parent(llvm::StringRef path) const;
  std::string model(llvm::StringRef path) const;
  mlir::LogicalResult seed(llvm::StringRef path, mlir::DictionaryAttr values,
                           unsigned precedence, llvm::StringRef model,
                           mlir::Location location, bool modelBased);
};
} // namespace talos
#endif
#endif
