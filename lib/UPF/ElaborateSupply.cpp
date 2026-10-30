#include "ElaborateSupply.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include <map>

using namespace mlir;
namespace talos {
LogicalResult lowerSupplyControls(sim::SimDesignOp design,
                                  ArrayRef<SupplyTableEntry> entries) {
  SmallVector<sim::SimSupplyControlOp> controls;
  design.walk([&](sim::SimSupplyControlOp op) { controls.push_back(op); });
  for (auto op : controls) {
    Location loc = op.getLoc();
    OpBuilder b(op->getContext());
    Value context = op.getContext(), name = op.getName(), on = op.getOn();
    Value voltage = op.getVoltage();
    Region &body = *op->getParentRegion();
    Block *entry = op->getBlock();
    Block *done = entry->splitBlock(Block::iterator(op));
    Value status = done->addArgument(b.getI1Type(), loc);
    op.getSuccess().replaceAllUsesWith(status);
    op.erase();
    auto block = [&] {
      auto *result = new Block;
      body.push_back(result);
      return result;
    };
    auto integer = [&](int64_t value, unsigned width) -> Value {
      return arith::ConstantIntOp::create(b, loc, value, width);
    };
    auto real = [&](double value) -> Value {
      return arith::ConstantOp::create(b, loc, b.getF64FloatAttr(value));
    };
    Block *lookup = block(), *error = block();
    b.setInsertionPointToEnd(entry);
    // IEEE 1801-2018 11.2.2/11.2.3.5.4 use signed32 microvolts and SV
    // nearest-integer conversion. Guard the rounded range before conversion,
    // including NaN/Inf, so native and wasm32 cannot overflow or trap.
    Value scaled = arith::MulFOp::create(b, loc, voltage, real(1000000.0));
    Value lower = arith::CmpFOp::create(b, loc, arith::CmpFPredicate::OGT,
                                        scaled, real(-2147483648.5));
    Value upper = arith::CmpFOp::create(b, loc, arith::CmpFPredicate::OLT,
                                        scaled, real(2147483647.5));
    Value valid = arith::AndIOp::create(b, loc, lower, upper);
    Value off = arith::XOrIOp::create(b, loc, on, integer(1, 1));
    valid = arith::OrIOp::create(b, loc, off, valid);
    cf::CondBranchOp::create(b, loc, valid, lookup, error);
    std::map<uint64_t, Block *> writes;
    b.setInsertionPointToEnd(lookup);
    for (const auto &item : entries) {
      Block *next = block();
      Block *matched = error;
      if (item.writable) {
        auto [found, inserted] = writes.try_emplace(item.storage, nullptr);
        if (inserted)
          found->second = block();
        matched = found->second;
      }
      Value literal = sim::SimStringLiteralOp::create(b, loc, item.name);
      Value compare = sim::SimStringCompareOp::create(b, loc, b.getI32Type(),
                                                      name, literal, false);
      Value equal = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                          compare, integer(0, 32));
      cf::CondBranchOp::create(b, loc, equal, matched, next);
      b.setInsertionPointToEnd(next);
    }
    cf::BranchOp::create(b, loc, error);
    for (auto [id, write] : writes) {
      b.setInsertionPointToEnd(write);
      Value safe = arith::SelectOp::create(b, loc, on, scaled, real(0.0));
      Value microvolts =
          sim::SimRealToIntegerOp::create(b, loc, b.getI32Type(), safe, true);
      Value bits = arith::ExtUIOp::create(b, loc, b.getI64Type(), microvolts);
      bits = arith::ShLIOp::create(b, loc, bits, integer(2, 64));
      bits = arith::OrIOp::create(b, loc, bits, integer(1, 64));
      // 11.2.3.3.5 explicitly writes OFF,0, unlike the general summary in
      // 9.3.1. Follow the function-specific text and algorithm. Publish the
      // complete pair once; propagation follows ordinary logic scheduling
      // (9.2.2/9.2.3), rather than synchronously running other HDL processes.
      Value value = arith::SelectOp::create(b, loc, on, bits, integer(0, 64));
      Value ref = sim::SimContextStorageOp::create(
          b, loc, sim::RefType::get(b.getContext(), b.getI64Type()), context,
          id);
      sim::SimRefStoreOp::create(b, loc, value, ref);
      cf::BranchOp::create(b, loc, done, ValueRange{integer(1, 1)});
    }
    b.setInsertionPointToEnd(error);
    // Invalid names/protected roots/voltages are runtime errors, only on the
    // executed path (11.2.3.3.4/.5). No root has been modified on this path.
    sim::SimErrorOp::create(b, loc, context);
    Value message = sim::SimBytesConstantOp::create(
        b, loc,
        "UPF supply control failed for %s: unknown/protected root or invalid "
        "voltage "
        "(IEEE 1801-2018 11.2.3.3.4/.5)");
    sim::SimDisplayOp::create(
        b, loc, context, integer(0x80000002u, 32), ValueRange{message, name},
        true, sim::Radix::Decimal, b.getDenseI32ArrayAttr({0, 8}), StringAttr{},
        StringAttr{}, IntegerAttr{}, IntegerAttr{});
    cf::BranchOp::create(b, loc, done, ValueRange{integer(0, 1)});
  }
  return success();
}
} // namespace talos
