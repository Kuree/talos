#ifndef TALOS_DIALECT_SCHEDULE_FIELDS_H
#define TALOS_DIALECT_SCHEDULE_FIELDS_H
#include "mlir/IR/BuiltinAttributes.h"
#include "talos/Dialect/Schedule/ScheduleFieldEnums.h"
// Deliberately forward-declare dialect attributes. Clients include Attrs.h
// only when they use a field whose payload is a Schedule dialect attribute.
#define GET_SCHEDULE_FIELD_TRAITS
#include "talos/Dialect/Schedule/ScheduleFields.h.inc"
namespace mlir {
class Operation;
}
namespace talos::schedule {
mlir::Attribute getAttribute(mlir::Operation *operation, Field field);
bool has(mlir::Operation *operation, Field field);
void set(mlir::Operation *operation, Field field, mlir::Attribute value);
mlir::Attribute remove(mlir::Operation *operation, Field field);

template <Field field> using FieldType = typename FieldTraits<field>::Type;
template <Field field> FieldType<field> get(mlir::Operation *operation) {
  return mlir::dyn_cast_or_null<FieldType<field>>(
      getAttribute(operation, field));
}
template <Field field> bool has(mlir::Operation *operation) {
  return has(operation, field);
}
template <Field field>
void set(mlir::Operation *operation, FieldType<field> value) {
  set(operation, field, value);
}
template <Field field> mlir::NamedAttribute named(FieldType<field> value) {
  return {mlir::StringAttr::get(value.getContext(), getFieldName(field)),
          value};
}
template <Field field> mlir::Attribute remove(mlir::Operation *operation) {
  return remove(operation, field);
}
template <typename Attr> Attr get(mlir::Operation *operation, Field field) {
  return mlir::dyn_cast_or_null<Attr>(getAttribute(operation, field));
}
/// The operation budget of one native inline decision: the module's configured
/// limit, 5000 by default. Zero removes the limit.
inline uint64_t getMaxInlineOperations(mlir::Operation *module) {
  auto limit = get<Field::MaxInlineOps>(module);
  uint64_t budget = limit ? limit.getUInt() : 5000;
  return budget ? budget : UINT64_MAX;
}
} // namespace talos::schedule
#endif
