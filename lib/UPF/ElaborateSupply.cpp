#include "ElaborateSupply.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include <map>

using namespace mlir;
namespace talos {
LogicalResult lowerSupplyAccesses(sim::SimDesignOp design,
                                  ArrayRef<SupplyTableEntry> entries) {
  SmallVector<Operation *> accesses;
  design.walk([&](Operation *op) {
    if (isa<sim::SimSupplyControlOp, sim::SimSupplyReadOp>(op))
      accesses.push_back(op);
  });
  for (auto *op : accesses) {
    auto control = dyn_cast<sim::SimSupplyControlOp>(op);
    bool writing = bool(control);
    Location loc = op->getLoc();
    OpBuilder b(op->getContext());
    Value context = op->getOperand(0), name = op->getOperand(1);
    Value on = writing ? control.getOn() : Value{};
    Value voltage = writing ? control.getVoltage() : Value{};
    Region &body = *op->getParentRegion();
    Block *entry = op->getBlock();
    Block *done = entry->splitBlock(Block::iterator(op));
    Value result =
        done->addArgument(writing ? b.getI1Type() : b.getI64Type(), loc);
    op->getResult(0).replaceAllUsesWith(result);
    op->erase();
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
    Value scaled;
    if (writing) {
      // IEEE 1801-2018 11.2.2/11.2.3.5.4 use signed32 microvolts and SV
      // nearest-integer conversion. Guard the rounded range before conversion,
      // including NaN/Inf, so native and wasm32 cannot overflow or trap.
      scaled = arith::MulFOp::create(b, loc, voltage, real(1000000.0));
      Value lower = arith::CmpFOp::create(b, loc, arith::CmpFPredicate::OGT,
                                          scaled, real(-2147483648.5));
      Value upper = arith::CmpFOp::create(b, loc, arith::CmpFPredicate::OLT,
                                          scaled, real(2147483647.5));
      Value valid = arith::AndIOp::create(b, loc, lower, upper);
      Value off = arith::XOrIOp::create(b, loc, on, integer(1, 1));
      valid = arith::OrIOp::create(b, loc, off, valid);
      cf::CondBranchOp::create(b, loc, valid, lookup, error);
    } else
      cf::BranchOp::create(b, loc, lookup);
    std::map<uint64_t, Block *> matches;
    b.setInsertionPointToEnd(lookup);
    for (const auto &item : entries) {
      Block *next = block();
      Block *matched = error;
      // Queries sample every root, including a protected computed output
      // (11.2.3.2.6). Write permissions must not hide such read-only aliases.
      if (!writing || item.writable) {
        auto [found, inserted] = matches.try_emplace(item.storage, nullptr);
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
    for (auto [id, matched] : matches) {
      b.setInsertionPointToEnd(matched);
      Value ref = sim::SimContextStorageOp::create(
          b, loc, sim::RefType::get(b.getContext(), b.getI64Type()), context,
          id);
      if (!writing) {
        // 11.2.3.2.1/.6 sample UPF_CURRENT_VALUE. Like an ordinary HDL read,
        // this does not synchronously run a pending switch propagation process
        // (9.2.3) or establish a deferred object mirror (11.2.3.4).
        Value value = sim::SimRefLoadOp::create(b, loc, b.getI64Type(), ref);
        cf::BranchOp::create(b, loc, done, ValueRange{value});
        continue;
      }
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
      sim::SimRefStoreOp::create(b, loc, value, ref);
      cf::BranchOp::create(b, loc, done, ValueRange{integer(1, 1)});
    }
    b.setInsertionPointToEnd(error);
    // Invalid accesses are runtime errors only on the executed path
    // (11.2.3.2.6 and 11.2.3.3.4/.5). No root is modified on this path.
    sim::SimErrorOp::create(b, loc, context);
    Value message = sim::SimBytesConstantOp::create(
        b, loc,
        writing ? "UPF supply control failed for %s: unknown/protected root or "
                  "invalid "
                  "voltage (IEEE 1801-2018 11.2.3.3.4/.5)"
                : "UPF supply query failed for %s: unknown supply "
                  "(IEEE 1801-2018 11.2.3.2.6)");
    sim::SimDisplayOp::create(
        b, loc, context, integer(0x80000002u, 32), ValueRange{message, name},
        true, sim::Radix::Decimal, b.getDenseI32ArrayAttr({0, 8}), StringAttr{},
        StringAttr{}, IntegerAttr{}, IntegerAttr{});
    // The standard does not specify an aggregate after a failed read.
    // Return UNDETERMINED,0 while retaining the unsuccessful simulation status.
    cf::BranchOp::create(
        b, loc, done, ValueRange{integer(writing ? 0 : 3, writing ? 1 : 64)});
  }
  return success();
}
} // namespace talos
