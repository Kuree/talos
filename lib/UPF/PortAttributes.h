#ifndef TALOS_UPF_PORTATTRIBUTES_H
#define TALOS_UPF_PORTATTRIBUTES_H
#ifdef TALOS_ENABLE_UPF
#include "ControlReference.h"
#include "DesignQuery.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include <map>
#include <tuple>

namespace talos {
class DesignAttributes;
// Per-bit 5.7.7 precedence over logical ports, never canonical storage aliases.
// The transaction interface also serves set_design_attributes on a port, so
// mixed instance/port commands cannot leave partially committed properties.
class PortAttributes {
public:
  struct Key {
    std::string model, path;
    bool operator<(const Key &other) const {
      return std::tie(model, path) < std::tie(other.model, other.path);
    }
  };
  struct Source {
    mlir::Attribute value;
    mlir::Location location;
    unsigned precedence;
    uint64_t low, width;
    std::string scope, top;
  };
  using Properties = std::map<std::string, llvm::SmallVector<Source, 1>>;
  using Delta = std::map<Key, Properties>;
  PortAttributes(mlir::ModuleOp module, const DesignQuery &queries,
                 const std::map<std::string, mlir::Operation *> &objects);
  mlir::LogicalResult initialize();
  bool empty() const { return properties.empty(); }
  int set(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
          llvm::StringRef scope, llvm::StringRef top, mlir::Location location,
          DesignAttributes &attributes,
          llvm::function_ref<mlir::FailureOr<std::string>(llvm::StringRef)>
              resolveSupply);
  mlir::LogicalResult
  prepareDesign(llvm::StringRef path, mlir::DictionaryAttr values,
                llvm::StringRef scope, llvm::StringRef top,
                mlir::Location location, Delta &delta,
                llvm::function_ref<void(const llvm::Twine &)> report);
  void commit(Delta &&delta);
  mlir::LogicalResult emit(mlir::OpBuilder &builder);

private:
  struct Port {
    Key key;
    std::string owner, name, model;
    mlir::Operation *declaration;
    uint64_t width;
    int64_t direction;
  };
  struct Segment {
    uint64_t low, width;
    const Source *source;
  };
  mlir::ModuleOp module;
  const DesignQuery &queries;
  const std::map<std::string, mlir::Operation *> &objects;
  std::map<Key, Port> ports;
  std::map<std::string, llvm::SmallVector<Key>> modelPorts;
  std::map<std::string, std::string> models;
  Delta properties;
  size_t work = 0;
  bool exceeded = false;
  bool charge(size_t count = 1);
  mlir::FailureOr<llvm::SmallVector<Segment>>
  resolve(llvm::ArrayRef<Source> sources,
          llvm::function_ref<void(const llvm::Twine &)> report);
  mlir::LogicalResult add(Delta &delta, const Key &key, llvm::StringRef name,
                          Source source,
                          llvm::function_ref<void(const llvm::Twine &)> report);
};
} // namespace talos
#endif
#endif
