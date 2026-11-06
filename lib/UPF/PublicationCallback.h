#ifndef TALOS_UPF_PUBLICATIONCALLBACK_H
#define TALOS_UPF_PUBLICATIONCALLBACK_H

#include "ControlValue.h"
#include "llvm/ADT/DenseMap.h"

namespace talos::upf_detail {
struct PublicationCallback {
  sim::SimFuncOp function;
  SmallVector<Descriptor> captures;
};

// Event-time callbacks must bind every persistent reference explicitly. Keep
// capture order in source operation order, independent of hash iteration.
inline FailureOr<PublicationCallback>
closePublicationCallback(sim::SimFuncOp fn, OpBuilder &b) {
  PublicationCallback result{fn, {}};
  llvm::DenseMap<std::pair<uint64_t, unsigned>, unsigned> indices;
  SmallVector<Operation *> lookups;
  fn.walk([&](Operation *op) {
    if (isa<sim::SimContextStorageOp, sim::SimContextNetOp>(op))
      lookups.push_back(op);
  });
  for (auto *op : lookups) {
    bool net = isa<sim::SimContextNetOp>(op);
    uint64_t id = net ? cast<sim::SimContextNetOp>(op).getId()
                      : cast<sim::SimContextStorageOp>(op).getId();
    auto entry = indices.try_emplace({id, net}, fn.getNumArguments());
    if (entry.second) {
      Type type = op->getResult(0).getType();
      Type element = net ? cast<sim::NetType>(type).getElementType()
                         : cast<sim::RefType>(type).getElementType();
      result.captures.push_back({id, element, net});
      auto attrs = b.getDictionaryAttr({sim::named<sim::metadata::CaptureKind>(
          sim::CaptureKindAttr::get(b.getContext(), sim::CaptureKind::Value))});
      if (failed(fn.insertArgument(fn.getNumArguments(), type, attrs,
                                   op->getLoc())))
        return failure();
    }
    op->getResult(0).replaceAllUsesWith(fn.getArgument(entry.first->second));
    op->erase();
  }
  return result;
}

inline SmallVector<Value>
publicationArguments(OpBuilder &b, Location loc, Value ctx,
                     const PublicationCallback &callback) {
  SmallVector<Value> result{ctx};
  for (auto capture : callback.captures)
    result.push_back(handle(b, loc, ctx, capture));
  return result;
}

inline Value bindPublication(OpBuilder &b, Location loc, Value ctx,
                             const PublicationCallback &callback,
                             bool dependencies) {
  auto values = publicationArguments(b, loc, ctx, callback);
  values.erase(values.begin());
  unsigned count = values.size();
  if (dependencies) {
    SmallVector<Value> watched(values);
    llvm::append_range(values, watched);
  }
  auto fn = callback.function;
  return sim::SimObserverBindOp::create(
      b, loc, sim::ObserverType::get(b.getContext(), fn.getResultTypes()[0]),
      fn.getSymNameAttr(), values, count);
}
} // namespace talos::upf_detail
#endif
