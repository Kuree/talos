//===- SimulationSAIFLowering.cpp - Table-driven activity registration ----===//

#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/SAIF/SAIFOps.h"
#include "talos/Runtime/StableHandle.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringMap.h"

using namespace mlir;

namespace talos::detail {
namespace {
std::string token(saif::IdentifierAttr identifier) {
  std::string result;
  for (char c : identifier.getName().getValue()) {
    if ((!llvm::isAlnum(c) && c != '_') || (result.empty() && llvm::isDigit(c)))
      result += '\\';
    result += c;
  }
  if (auto index = identifier.getIndex())
    result += "[" + index.getValue().str() + "]";
  return result;
}
} // namespace

LogicalResult materializeSAIFRegistration(ModuleOp module, OpBuilder &builder,
                                          Value runtimeContext,
                                          const NativeStateLayout &stateLayout,
                                          int64_t precisionFs) {
  auto bindings = saif::get<saif::Bindings>(module);
  if (!bindings || precisionFs <= 0)
    return module.emitError(
        "SAIF requires a prepared inventory and positive time precision");
  MLIRContext *context = module.getContext();
  Location location = module.getLoc();
  Type pointer = LLVM::LLVMPointerType::get(context);
  Type i8 = builder.getI8Type(), i32 = builder.getI32Type(),
       i64 = builder.getI64Type();
  Type voidType = LLVM::LLVMVoidType::get(context);
  auto rowType =
      LLVM::LLVMStructType::getLiteral(context, SmallVector<Type>(7, i64));
  SmallVector<Attribute> rows;
  std::string pool;
  llvm::StringMap<uint64_t> offsets;
  auto intern = [&](StringRef value) {
    auto [it, inserted] = offsets.try_emplace(value, pool.size());
    if (inserted)
      pool.append(value.data(), value.size());
    return it->second;
  };
  auto internString = [&](StringRef value) {
    return intern((value + Twine('\0')).str());
  };
  uint64_t outputOffset = internString(saif::get<saif::Output>(module));
  for (Attribute attr : bindings) {
    auto binding = cast<saif::BindingAttr>(attr);
    const auto &handles =
        binding.getSourceIsNet() ? stateLayout.nets : stateLayout.storage;
    auto found = handles.find(binding.getSourceId());
    if (found == handles.end() || binding.getSourceLow() > INT64_MAX)
      return module.emitError(
          "SAIF observation has no representable native state handle");
    uint64_t handle =
        talos_rt_stable_handle_offset(found->second, binding.getSourceLow());
    if (handle == UINT64_MAX)
      return module.emitError("SAIF bit exceeds the stable state handle range");
    talos_rt_stable_handle_v1 decoded{};
    if (!talos_rt_stable_handle_decode(handle, &decoded))
      return module.emitError("SAIF observation has an invalid state handle");
    const auto *bound = stateLayout.findBound(decoded.id);
    if (!bound || decoded.offset < 0 ||
        uint64_t(decoded.offset) >= bound->width)
      return module.emitError("SAIF observation exceeds its native state root");
    std::string instance;
    for (Attribute component : binding.getInstance().getComponents()) {
      instance += token(cast<saif::IdentifierAttr>(component));
      instance += '\0';
    }
    uint64_t instanceOffset = intern(instance);
    uint64_t signalOffset = internString(token(binding.getSignal()));
    uint64_t virtualOffset = binding.getVirtualType()
                                 ? internString(binding.getVirtualType())
                                 : UINT64_MAX;
    rows.push_back(integerStructAttr(
        rowType, {handle, instanceOffset, instance.size(), signalOffset,
                  virtualOffset, binding.getPort(), binding.getInitial()}));
  }
  auto cellRowType =
      LLVM::LLVMStructType::getLiteral(context, SmallVector<Type>(5, i64));
  SmallVector<Attribute> cellRows, cellWords;
  if (auto cells = saif::get<saif::Cells>(module)) {
    for (Attribute value : cells) {
      auto cell = cast<saif::CellBindingAttr>(value);
      SmallVector<uint64_t> words{1, cell.getPins().size(),
                                  cell.getGroups().size()};
      DenseMap<saif::IdentifierAttr, uint64_t> pins;
      for (auto [index, pinValue] : llvm::enumerate(cell.getPins())) {
        auto pin = cast<saif::PinBindingAttr>(pinValue);
        pins[pin.getName()] = index;
        words.append({pin.getObservation(), uint64_t(pin.getOutput())});
      }
      for (Attribute groupValue : cell.getGroups()) {
        auto group = cast<saif::GroupAttr>(groupValue);
        words.append({group.getObservation(),
                      uint64_t(group.getLeakage()) |
                          (uint64_t(group.getConditional()) << 1),
                      group.getRules().size()});
        for (Attribute ruleValue : group.getRules()) {
          auto rule = cast<saif::RuleAttr>(ruleValue);
          auto condition = rule.getCondition();
          words.append({uint64_t(rule.getSplitEdges()),
                        condition ? condition.getTokens().size() : 0,
                        rule.getPaths().size()});
          if (condition)
            for (Attribute tokenValue : condition.getTokens()) {
              auto token = cast<saif::ConditionTokenAttr>(tokenValue);
              words.append({uint64_t(token.getOpcode()),
                            token.getPin() ? pins.lookup(token.getPin()) : 0});
            }
          for (Attribute relatedValue : rule.getPaths()) {
            auto related = cast<saif::RelatedAttr>(relatedValue);
            words.append(
                {uint64_t(related.getIsDefault()), related.getPins().size()});
            for (Attribute pin : related.getPins())
              words.push_back(pins.lookup(cast<saif::IdentifierAttr>(pin)));
          }
        }
      }
      uint64_t wordOffset = cellWords.size();
      for (uint64_t word : words)
        cellWords.push_back(builder.getI64IntegerAttr(word));
      std::string instance;
      for (Attribute component : cell.getInstance().getComponents()) {
        instance += token(cast<saif::IdentifierAttr>(component));
        instance += '\0';
      }
      cellRows.push_back(integerStructAttr(
          cellRowType,
          {intern(instance), instance.size(),
           internString(cell.getCell().getValue()), wordOffset, words.size()}));
    }
  }
  constexpr StringLiteral stringsName = "__talos_saif_strings";
  constexpr StringLiteral tableName = "__talos_saif_bindings";
  makeByteArrayGlobal(module, location, stringsName, pool);
  makeConstantGlobal(module, location,
                     LLVM::LLVMArrayType::get(rowType, rows.size()), tableName,
                     LLVM::Linkage::Internal, 8, ArrayAttr::get(context, rows));
  constexpr StringLiteral cellTableName = "__talos_saif_cells";
  constexpr StringLiteral cellWordsName = "__talos_saif_cell_words";
  makeConstantGlobal(module, location,
                     LLVM::LLVMArrayType::get(cellRowType, cellRows.size()),
                     cellTableName, LLVM::Linkage::Internal, 8,
                     ArrayAttr::get(context, cellRows));
  makeConstantGlobal(module, location,
                     LLVM::LLVMArrayType::get(i64, cellWords.size()),
                     cellWordsName, LLVM::Linkage::Internal, 8,
                     ArrayAttr::get(context, cellWords));
  auto address = [&](Value offset) -> Value {
    return LLVM::GEPOp::create(
        builder, location, pointer, i8,
        LLVM::AddressOfOp::create(builder, location, pointer, stringsName),
        ArrayRef<LLVM::GEPArg>{offset});
  };
  auto checked = [&](StringRef name, Value ctx, ValueRange args) {
    Value status =
        LLVM::CallOp::create(builder, location, TypeRange{i32}, name, args)
            .getResult();
    LLVM::CallOp::create(builder, location, TypeRange{},
                         "talos_rt_v1_scheduler_fail", ValueRange{ctx, status});
  };
  checked(
      "talos_rt_v1_saif_configure", runtimeContext,
      ValueRange{runtimeContext,
                 address(llvmConstant(builder, location, i64, outputOffset)),
                 llvmConstant(builder, location, i64, precisionFs)});

  // Keep registration code constant-sized even for a million observed bits.
  // Tables contain only integer offsets, so LLVM can retain direct constant
  // initializers instead of building one insertion operation per byte.
  if (!rows.empty()) {
    LLVM::LLVMFuncOp helper;
    {
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToEnd(module.getBody());
      helper = LLVM::LLVMFuncOp::create(
          builder, location, "__talos_register_saif",
          LLVM::LLVMFunctionType::get(voidType, {pointer}, false),
          LLVM::Linkage::Internal);
      helper.setNoInline(true);
      Block *entry = helper.addEntryBlock(builder);
      auto *header = new Block, *body = new Block, *exit = new Block;
      for (Block *block : {header, body, exit})
        helper.getBody().push_back(block);
      Value ctx = entry->getArgument(0);
      Value index = header->addArgument(i64, location);
      builder.setInsertionPointToStart(entry);
      LLVM::BrOp::create(builder, location,
                         ValueRange{llvmConstant(builder, location, i64, 0)},
                         header);
      builder.setInsertionPointToStart(header);
      Value more = LLVM::ICmpOp::create(
          builder, location, LLVM::ICmpPredicate::ult, index,
          llvmConstant(builder, location, i64, rows.size()));
      LLVM::CondBrOp::create(builder, location, more, body, exit);
      builder.setInsertionPointToStart(body);
      auto field = [&](int32_t column) -> Value {
        Value at = LLVM::GEPOp::create(
            builder, location, pointer, rowType,
            LLVM::AddressOfOp::create(builder, location, pointer, tableName),
            ArrayRef<LLVM::GEPArg>{index, column});
        return LLVM::LoadOp::create(builder, location, i64, at, 8);
      };
      Value virtualOffset = field(4);
      Value hasVirtualType = LLVM::ICmpOp::create(
          builder, location, LLVM::ICmpPredicate::ne, virtualOffset,
          llvmConstant(builder, location, i64, UINT64_MAX));
      Value virtualType = LLVM::SelectOp::create(
          builder, location, hasVirtualType, address(virtualOffset),
          LLVM::ZeroOp::create(builder, location, pointer));
      checked("talos_rt_v1_saif_bind", ctx,
              ValueRange{
                  ctx, field(0), address(field(1)), field(2), address(field(3)),
                  LLVM::TruncOp::create(builder, location, i32, field(5)),
                  virtualType,
                  LLVM::TruncOp::create(builder, location, i32, field(6))});
      Value next = LLVM::AddOp::create(builder, location, index,
                                       llvmConstant(builder, location, i64, 1));
      LLVM::BrOp::create(builder, location, ValueRange{next}, header);
      builder.setInsertionPointToStart(exit);
      LLVM::ReturnOp::create(builder, location, ValueRange{});
    }
    LLVM::CallOp::create(builder, location, TypeRange{}, helper.getSymName(),
                         runtimeContext);
  }
  if (!cellRows.empty()) {
    getOrDeclareLLVMFunction(module, "talos_rt_v1_saif_cell", i32,
                             {pointer, pointer, i64, pointer, pointer, i64});
    LLVM::LLVMFuncOp helper;
    {
      OpBuilder::InsertionGuard guard(builder);
      builder.setInsertionPointToEnd(module.getBody());
      helper = LLVM::LLVMFuncOp::create(
          builder, location, "__talos_register_saif_cells",
          LLVM::LLVMFunctionType::get(voidType, {pointer}, false),
          LLVM::Linkage::Internal);
      helper.setNoInline(true);
      Block *entry = helper.addEntryBlock(builder);
      auto *header = new Block, *body = new Block, *exit = new Block;
      for (Block *block : {header, body, exit})
        helper.getBody().push_back(block);
      Value ctx = entry->getArgument(0);
      Value index = header->addArgument(i64, location);
      builder.setInsertionPointToStart(entry);
      LLVM::BrOp::create(builder, location,
                         ValueRange{llvmConstant(builder, location, i64, 0)},
                         header);
      builder.setInsertionPointToStart(header);
      Value more = LLVM::ICmpOp::create(
          builder, location, LLVM::ICmpPredicate::ult, index,
          llvmConstant(builder, location, i64, cellRows.size()));
      LLVM::CondBrOp::create(builder, location, more, body, exit);
      builder.setInsertionPointToStart(body);
      auto field = [&](int32_t column) -> Value {
        Value at =
            LLVM::GEPOp::create(builder, location, pointer, cellRowType,
                                LLVM::AddressOfOp::create(
                                    builder, location, pointer, cellTableName),
                                ArrayRef<LLVM::GEPArg>{index, column});
        return LLVM::LoadOp::create(builder, location, i64, at, 8);
      };
      Value plan = LLVM::GEPOp::create(
          builder, location, pointer, i64,
          LLVM::AddressOfOp::create(builder, location, pointer, cellWordsName),
          ArrayRef<LLVM::GEPArg>{field(3)});
      checked("talos_rt_v1_saif_cell", ctx,
              ValueRange{ctx, address(field(0)), field(1), address(field(2)),
                         plan, field(4)});
      Value next = LLVM::AddOp::create(builder, location, index,
                                       llvmConstant(builder, location, i64, 1));
      LLVM::BrOp::create(builder, location, ValueRange{next}, header);
      builder.setInsertionPointToStart(exit);
      LLVM::ReturnOp::create(builder, location, ValueRange{});
    }
    LLVM::CallOp::create(builder, location, TypeRange{}, helper.getSymName(),
                         runtimeContext);
  }
  checked("talos_rt_v1_saif_seal", runtimeContext, ValueRange{runtimeContext});
  return success();
}
} // namespace talos::detail
