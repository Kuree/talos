//===- SAIFFrontendTest.cpp - Import boundary and verifier scaling -------===//

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Verifier.h"
#include "talos/Dialect/SAIF/SAIFOps.h"
#include "talos/Frontend/SAIF.h"
#include "llvm/Support/raw_ostream.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <string>
#include <utility>

using namespace mlir;

static constexpr llvm::StringLiteral header = R"(
  (SAIFVERSION "2.0") (DIRECTION "backward")
  (DESIGN) (DATE) (VENDOR) (PROGRAM_NAME) (PROGRAM_VERSION)
  (DIVIDER) (TIMESCALE) (DURATION 10)
)";

static constexpr llvm::StringLiteral forwardHeader = R"(
  (SAIFVERSION "2.0") (DIRECTION "forward")
  (DESIGN) (DATE) (VENDOR) (PROGRAM_NAME) (PROGRAM_VERSION) (DIVIDER)
)";

static std::string file(llvm::StringRef headers, llvm::StringRef body) {
  return (llvm::Twine("(SAIFILE ") + headers + " " + body + ")").str();
}

static bool check(bool value, llvm::StringRef message) {
  if (!value)
    llvm::errs() << message << '\n';
  return value;
}

static bool requiredStorageTests(MLIRContext &context,
                                 std::string &diagnostic) {
  auto emit = [&] { return emitError(UnknownLoc::get(&context)); };
  auto rejects = [&](auto create, llvm::StringRef expected) {
    diagnostic.clear();
    return check(!create(), "checked construction accepted missing storage") &&
           check(llvm::StringRef(diagnostic).contains(expected), diagnostic);
  };
  using namespace talos::saif;
  auto one = NumberAttr::get(&context, StringAttr::get(&context, "1"));
  auto ns = StringAttr::get(&context, "ns");
  if (!rejects(
          [&] { return NumberAttr::getChecked(emit, &context, StringAttr()); },
          "number requires a spelling") ||
      !rejects(
          [&] {
            return IdentifierAttr::getChecked(emit, &context, StringAttr(),
                                              StringAttr());
          },
          "identifier requires a name") ||
      !rejects(
          [&] { return PathAttr::getChecked(emit, &context, ArrayAttr()); },
          "path requires a component array") ||
      !rejects(
          [&] {
            return ConditionAttr::getChecked(emit, &context, ArrayAttr());
          },
          "condition requires a token array") ||
      !rejects(
          [&] {
            return TimeScaleAttr::getChecked(emit, &context, NumberAttr(), ns);
          },
          "TIMESCALE requires an amount and unit") ||
      !rejects(
          [&] {
            return TimeScaleAttr::getChecked(emit, &context, one, StringAttr());
          },
          "TIMESCALE requires an amount and unit"))
    return false;

  // Cheap construction invariants must not absorb file-level semantics.
  diagnostic.clear();
  auto illegal = TimeScaleAttr::getChecked(
      emit, &context, NumberAttr::get(&context, StringAttr::get(&context, "2")),
      StringAttr::get(&context, "minutes"));
  return check(illegal && diagnostic.empty(),
               "attribute construction performed semantic validation");
}

static bool positiveGrammarTests(MLIRContext &context,
                                 std::string &diagnostic) {
  for (llvm::StringRef amount : {"1", "10", "100"}) {
    for (llvm::StringRef unit : {"s", "ms", "us", "ns", "ps", "fs"}) {
      std::string source = file(header, "");
      source.replace(
          source.find("(TIMESCALE)"), 11,
          (llvm::Twine("(TIMESCALE ") + amount + " " + unit + ")").str());
      auto module = talos::frontend::importSAIF("units.saif", source, context);
      if (!check(succeeded(module), diagnostic))
        return false;
      talos::saif::TimeScaleAttr scale;
      (*module)->walk([&](talos::saif::HeaderOp op) {
        if (op.getKind() == talos::saif::HeaderKind::TimeScale)
          scale = op.getScaleAttr();
      });
      if (!check(scale &&
                     scale.getAmount().getSpelling().getValue() == amount &&
                     scale.getUnit().getValue() == unit,
                 "legal timescale did not retain its amount and unit"))
        return false;
    }
  }

  std::pair<llvm::StringRef, llvm::StringRef> expressions[] = {
      {"A*B*C", "AB*C*"}, {"A^B^C", "AB^C^"},   {"A|B|C", "AB|C|"},
      {"!!A", "A!!"},     {"A*(B|C)", "ABC|*"}, {"A*!(B*C)", "ABC*!*"}};
  for (auto [expression, expected] : expressions) {
    auto body = (llvm::Twine("(INSTANCE top (LEAKAGE (COND ") + expression +
                 " (T1 1))))")
                    .str();
    auto module = talos::frontend::importSAIF("expression.saif",
                                              file(header, body), context);
    if (!check(succeeded(module), diagnostic))
      return false;
    talos::saif::ConditionAttr condition;
    (*module)->walk(
        [&](talos::saif::WhenOp op) { condition = op.getConditionAttr(); });
    std::string postfix;
    for (Attribute attr : condition.getTokens()) {
      auto token = cast<talos::saif::ConditionTokenAttr>(attr);
      using Opcode = talos::saif::ConditionOpcode;
      switch (token.getOpcode()) {
      case Opcode::Pin:
        postfix += token.getPin().getName().getValue();
        break;
      case Opcode::Not:
        postfix += '!';
        break;
      case Opcode::And:
        postfix += '*';
        break;
      case Opcode::Xor:
        postfix += '^';
        break;
      case Opcode::Or:
        postfix += '|';
        break;
      }
    }
    if (!check(postfix == expected, "condition associativity/grouping changed"))
      return false;
  }
  return true;
}

static bool resourceLimitTests(MLIRContext &context, std::string &diagnostic) {
  auto source = file(header, "(INSTANCE top (NET (q (TC 1))))");
  std::string documents[] = {
      source,
      file(header, "(INSTANCE top (PORT (Y (COND A (IOPATH B (TC 1))))))"),
      file(forwardHeader,
           "(LIBRARY \"L\" (MODULE C (PORT Y (COND A (IOPATH B) COND_DEFAULT))"
           " (LEAKAGE (COND A COND_DEFAULT))))"),
      file(forwardHeader,
           "(INSTANCE top (PORT (a u.I \"sequential\")) (NET (q u.Q)))")};
  for (const auto &document : documents) {
    auto complete =
        talos::frontend::importSAIF("limit.saif", document, context);
    if (!check(succeeded(complete), diagnostic))
      return false;
    uint64_t operations = 0;
    Operation *root = (*complete)->getOperation();
    root->walk([&](Operation *op) { operations += op != root; });
    talos::frontend::SAIFResourceLimits limits;
    limits.maxOperations = operations;
    if (!check(succeeded(talos::frontend::importSAIF("limit.saif", document,
                                                     context, false, limits)),
               diagnostic))
      return false;
    // Stop immediately before each operation, including every container kind.
    // This exercises partial-IR cleanup and makes the count boundary exact.
    for (uint64_t limit = 0; limit < operations; ++limit) {
      limits.maxOperations = limit;
      diagnostic.clear();
      if (!check(failed(talos::frontend::importSAIF("limit.saif", document,
                                                    context, false, limits)) &&
                     llvm::StringRef(diagnostic).contains("operation count"),
                 "operation boundary was not enforced"))
        return false;
    }
  }

  talos::frontend::SAIFResourceLimits limits;
  limits.maxInputBytes = source.size();
  if (!check(succeeded(talos::frontend::importSAIF("bytes.saif", source,
                                                   context, false, limits)),
             diagnostic))
    return false;
  --limits.maxInputBytes;
  diagnostic.clear();
  if (!check(failed(talos::frontend::importSAIF("bytes.saif", source, context,
                                                false, limits)) &&
                 llvm::StringRef(diagnostic).contains("byte limit"),
             "byte boundary was not enforced"))
    return false;

  limits = {};
  limits.maxNestingDepth = 4;
  if (!check(succeeded(talos::frontend::importSAIF("depth.saif", source,
                                                   context, false, limits)),
             diagnostic))
    return false;
  --limits.maxNestingDepth;
  diagnostic.clear();
  if (!check(failed(talos::frontend::importSAIF("depth.saif", source, context,
                                                false, limits)) &&
                 llvm::StringRef(diagnostic).contains("record nesting"),
             "record depth boundary was not enforced"))
    return false;

  source = file(header, "(INSTANCE top (PORT (Y (COND A|B (TC 1)))))");
  limits = {};
  limits.maxConditionTokens = 3;
  if (!check(succeeded(talos::frontend::importSAIF("tokens.saif", source,
                                                   context, false, limits)),
             diagnostic))
    return false;
  --limits.maxConditionTokens;
  diagnostic.clear();
  return check(failed(talos::frontend::importSAIF("tokens.saif", source,
                                                  context, false, limits)) &&
                   llvm::StringRef(diagnostic).contains("token limit"),
               "condition token boundary was not enforced");
}

static bool cellPlanTests(MLIRContext &context, std::string &diagnostic) {
  using namespace talos::saif;
  auto module =
      OwningOpRef<ModuleOp>(ModuleOp::create(UnknownLoc::get(&context)));
  auto a = IdentifierAttr::get(&context, StringAttr::get(&context, "A"),
                               StringAttr{});
  auto y = IdentifierAttr::get(&context, StringAttr::get(&context, "Y"),
                               StringAttr{});
  auto instance = PathAttr::get(&context, ArrayAttr::get(&context, {a}));
  auto array = [&](ArrayRef<Attribute> items) {
    return ArrayAttr::get(&context, items);
  };
  set<Output>(*module, StringAttr::get(&context, "out.saif"));
  set<Bindings>(
      *module,
      array(
          {BindingAttr::get(&context, 0, false, 0, instance, a, true, 0, {}),
           BindingAttr::get(&context, 0, false, 1, instance, y, true, 0, {})}));
  auto pins = array({PinBindingAttr::get(&context, a, 0, false),
                     PinBindingAttr::get(&context, y, 1, true)});
  auto condition = ConditionAttr::get(
      &context,
      array({ConditionTokenAttr::get(&context, ConditionOpcode::Pin, a)}));
  auto paths = array({RelatedAttr::get(&context, array({a}), false)});
  auto rule = RuleAttr::get(&context, condition, true, paths);
  auto group = GroupAttr::get(&context, 1, false, true, array({rule}));
  auto make = [&](ArrayAttr selectedPins, ArrayAttr groups) {
    return CellBindingAttr::get(&context, instance,
                                StringAttr::get(&context, "cell"), selectedPins,
                                groups);
  };
  auto valid = make(pins, array({group}));
  set<Cells>(*module, array({valid}));
  if (!check(succeeded(verify(*module)), diagnostic))
    return false;
  auto rejects = [&](CellBindingAttr cell, StringRef expected) {
    diagnostic.clear();
    set<Cells>(*module, array({cell}));
    return check(failed(verify(*module)),
                 "cell verifier accepted illegal plan") &&
           check(StringRef(diagnostic).contains(expected), diagnostic);
  };
  if (!rejects(make(array({PinBindingAttr::get(&context, a, 0, true),
                           PinBindingAttr::get(&context, y, 1, true)}),
                    array({group})),
               "bound input pins") ||
      !rejects(make(pins, array({GroupAttr::get(&context, 0, false, true,
                                                array({rule}))})),
               "require an output pin") ||
      !rejects(
          make(pins,
               array({GroupAttr::get(
                   &context, 1, false, true,
                   array({RuleAttr::get(&context, {}, false, array({}))}))})),
          "nondefault rule") ||
      !rejects(
          make(pins,
               array({GroupAttr::get(
                   &context, 1, false, false,
                   array({RuleAttr::get(&context, {}, true, array({}))}))})),
          "edge splitting requires conditions") ||
      !rejects(make(pins, array({GroupAttr::get(
                              &context, UINT64_MAX, true, false,
                              array({RuleAttr::get(&context, {}, false,
                                                   array({}))}))})),
               "leakage groups require conditions") ||
      !rejects(
          make(pins,
               array({GroupAttr::get(
                   &context, 1, false, true,
                   array({RuleAttr::get(&context, condition, false,
                                        array({RelatedAttr::get(
                                            &context, array({}), true)}))}))})),
          "require a named related input"))
    return false;
#ifdef NDEBUG
  if (!rejects(CellBindingAttr::get(&context, {}, {}, {}, {}),
               "binding shape") ||
      !rejects(
          make(array({PinBindingAttr::get(&context, {}, 0, false)}), array({})),
          "pin binding") ||
      !rejects(
          make(pins, array({GroupAttr::get(&context, 1, false, true, {})})),
          "characterization group") ||
      !rejects(
          make(pins,
               array({GroupAttr::get(
                   &context, 1, false, true,
                   array({RuleAttr::get(&context, condition, false, {})}))})),
          "priority rule"))
    return false;
#endif
  return true;
}

static int apiTests(MLIRContext &context) {
  std::string diagnostic;
  ScopedDiagnosticHandler handler(&context, [&](Diagnostic &error) {
    llvm::raw_string_ostream stream(diagnostic);
    error.print(stream);
    stream << '\n';
    return success();
  });
  auto rejects = [&](Operation *op, llvm::StringRef expected) {
    diagnostic.clear();
    return check(failed(verify(op)), "verifier accepted illegal IR") &&
           check(llvm::StringRef(diagnostic).contains(expected), diagnostic);
  };
  auto source =
      (llvm::Twine("(SAIFILE ") + header + " (INSTANCE top (NET (q (TC 1)))))")
          .str();
  auto module = talos::frontend::importSAIF("valid.saif", source, context);
  if (!check(succeeded(module), diagnostic))
    return 1;
  if (!cellPlanTests(context, diagnostic))
    return 1;
  if (!requiredStorageTests(context, diagnostic))
    return 1;

#ifdef NDEBUG
  // get() assumes valid storage, unlike getChecked(). Even if a release caller
  // violates that contract, verification must diagnose it without printing
  // the malformed attribute (the null amount formerly crashed the printer).
  talos::saif::HeaderOp scaleHeader;
  (*module)->walk([&](talos::saif::HeaderOp op) {
    if (op.getKind() == talos::saif::HeaderKind::TimeScale)
      scaleHeader = op;
  });
  auto originalScale = scaleHeader.getScaleAttr();
  auto ns = StringAttr::get(&context, "ns");
  auto one =
      talos::saif::NumberAttr::get(&context, StringAttr::get(&context, "1"));
  for (auto bad :
       {talos::saif::TimeScaleAttr::get(&context, talos::saif::NumberAttr(),
                                        ns),
        talos::saif::TimeScaleAttr::get(&context, one, StringAttr()),
        talos::saif::TimeScaleAttr::get(
            &context, talos::saif::NumberAttr::get(&context, StringAttr()),
            ns)}) {
    scaleHeader.setScaleAttr(bad);
    if (!rejects(**module, "TIMESCALE requires an amount and unit"))
      return 1;
  }
  scaleHeader.setScaleAttr(originalScale);
  auto planModule =
      OwningOpRef<ModuleOp>(ModuleOp::create(UnknownLoc::get(&context)));
  talos::saif::set<talos::saif::Output>(*planModule,
                                        StringAttr::get(&context, "out.saif"));
  auto q = talos::saif::IdentifierAttr::get(
      &context, StringAttr::get(&context, "q"), StringAttr{});
  auto top =
      talos::saif::PathAttr::get(&context, ArrayAttr::get(&context, {q}));
  for (auto bad : {talos::saif::BindingAttr::get(&context, 0, false, 0,
                                                 talos::saif::PathAttr(), q,
                                                 false, 0, StringAttr{}),
                   talos::saif::BindingAttr::get(&context, 0, false, 0, top,
                                                 talos::saif::IdentifierAttr(),
                                                 false, 0, StringAttr{})}) {
    talos::saif::set<talos::saif::Bindings>(*planModule,
                                            ArrayAttr::get(&context, {bad}));
    if (!rejects(*planModule, "invalid SAIF observation binding"))
      return 1;
  }
#endif

  // This must work with assertions enabled: attribute construction represents
  // source data, and must not check its semantic validity before the verifier.
  auto illegal = (llvm::Twine("(SAIFILE ") + header +
                  " (INSTANCE top (NET (q (TC 1e9999)))))")
                     .str();
  diagnostic.clear();
  auto parsed = talos::frontend::importSAIF("illegal.saif", illegal, context,
                                            /*verifyIR=*/false);
  if (!check(succeeded(parsed) && diagnostic.empty(),
             "syntax-only import performed a semantic check") ||
      !rejects(**parsed, "number must be finite"))
    return 1;

  talos::saif::MetricOp metric;
  (*module)->walk([&](talos::saif::MetricOp op) { metric = op; });
  auto original = metric.getValue();
  metric.setValueAttr(
      talos::saif::NumberAttr::get(&context, StringAttr::get(&context, "-1")));
  if (!rejects(**module, "nonnegative decimal"))
    return 1;
  metric.setValueAttr(original);
  metric->setAttr("kind",
                  IntegerAttr::get(IntegerType::get(&context, 32), 999));
  if (!rejects(**module, "kind"))
    return 1;

  auto conditional =
      file(header, "(INSTANCE top (PORT (Y (COND A (IOPATH B (TC 1))))))");
  parsed = talos::frontend::importSAIF("condition.saif", conditional, context);
  if (!check(succeeded(parsed), diagnostic))
    return 1;
  talos::saif::WhenOp when;
  (*parsed)->walk([&](talos::saif::WhenOp op) { when = op; });
  auto originalCondition = when.getConditionAttr();
  auto token = talos::saif::ConditionTokenAttr::get(
      &context, static_cast<talos::saif::ConditionOpcode>(999), {});
  when.setConditionAttr(talos::saif::ConditionAttr::get(
      &context, ArrayAttr::get(&context, {token})));
  if (!rejects(**parsed, "unknown condition opcode"))
    return 1;
  when.setConditionAttr(talos::saif::ConditionAttr::get(
      &context,
      ArrayAttr::get(&context, {StringAttr::get(&context, "not-a-token")})));
  if (!rejects(**parsed, "condition contains a non-token"))
    return 1;
  when.setConditionAttr(talos::saif::ConditionAttr::get(
      &context,
      ArrayAttr::get(&context,
                     {talos::saif::ConditionTokenAttr::get(
                         &context, talos::saif::ConditionOpcode::Not, {})})));
  if (!rejects(**parsed, "condition postfix stack underflow"))
    return 1;
  when.setConditionAttr(originalCondition);

  talos::saif::InstanceOp instance;
  talos::saif::PathOp path;
  (*parsed)->walk([&](talos::saif::InstanceOp op) { instance = op; });
  (*parsed)->walk([&](talos::saif::PathOp op) { path = op; });
  auto originalName = instance.getName();
  instance.setNameAttr(talos::saif::PathAttr::get(
      &context, ArrayAttr::get(&context, {StringAttr::get(&context, "top")})));
  if (!rejects(**parsed, "path requires 1..4096 identifier components"))
    return 1;
  instance.setNameAttr(originalName);
  auto originalPins = path.getPins();
  path.setPinsAttr(ArrayAttr::get(&context, {StringAttr::get(&context, "B")}));
  if (!rejects(**parsed, "related pins must be simple identifiers"))
    return 1;
  path.setPinsAttr(originalPins);

  auto scaleSource = (llvm::Twine("(SAIFILE ") + header + ")").str();
  scaleSource.replace(scaleSource.find("(TIMESCALE)"), 11, "(TIMESCALE 2 ns)");
  diagnostic.clear();
  parsed =
      talos::frontend::importSAIF("scale.saif", scaleSource, context, false);
  if (!check(succeeded(parsed) && diagnostic.empty(),
             "parser rejected a semantic timescale error") ||
      !rejects(**parsed, "TIMESCALE amount"))
    return 1;

  talos::frontend::SAIFResourceLimits limits;
  limits.maxOperations = 1;
  diagnostic.clear();
  if (!check(failed(talos::frontend::importSAIF("limit.saif", source, context,
                                                false, limits)) &&
                 llvm::StringRef(diagnostic).contains("operation count"),
             "operation limit was not enforced"))
    return 1;
  if (!positiveGrammarTests(context, diagnostic) ||
      !resourceLimitTests(context, diagnostic))
    return 1;
  llvm::outs() << "PASS: SAIF syntax/verification boundary and unchecked IR\n";
  return 0;
}

static int benchmark(MLIRContext &context, unsigned count) {
  std::string source = R"((SAIFILE
    (SAIFVERSION "2.0" "lib") (DIRECTION "forward")
    (DESIGN) (DATE) (VENDOR) (PROGRAM_NAME) (PROGRAM_VERSION) (DIVIDER)
    (LIBRARY "L" (MODULE C (PORT Y ()";
  for (unsigned i = 0; i < count; ++i)
    source += "IOPATH pin" + std::to_string(i) + " ";
  source += ")))))";
  auto module =
      talos::frontend::importSAIF("scaling.saif", source, context, false);
  if (failed(module))
    return 1;
  std::array<double, 3> samples;
  for (double &sample : samples) {
    auto start = std::chrono::steady_clock::now();
    if (failed(verify(**module)))
      return 1;
    sample = std::chrono::duration<double, std::milli>(
                 std::chrono::steady_clock::now() - start)
                 .count();
  }
  std::sort(samples.begin(), samples.end());
  llvm::outs() << "paths=" << count << " verify_ms=" << samples[1] << '\n';
  return 0;
}

static int benchmarkBindings(MLIRContext &context, unsigned count) {
  context.getOrLoadDialect<talos::saif::SAIFDialect>();
  auto module =
      OwningOpRef<ModuleOp>(ModuleOp::create(UnknownLoc::get(&context)));
  auto instance = talos::saif::PathAttr::get(
      &context,
      ArrayAttr::get(&context, {talos::saif::IdentifierAttr::get(
                                   &context, StringAttr::get(&context, "top"),
                                   StringAttr{})}));
  SmallVector<Attribute> bindings;
  for (unsigned index = 0; index < count; ++index) {
    auto signal = talos::saif::IdentifierAttr::get(
        &context, StringAttr::get(&context, "q"),
        StringAttr::get(&context, std::to_string(index)));
    bindings.push_back(talos::saif::BindingAttr::get(
        &context, 0, false, index, instance, signal, false, 0, StringAttr{}));
  }
  talos::saif::set<talos::saif::Output>(*module,
                                        StringAttr::get(&context, "out.saif"));
  talos::saif::set<talos::saif::Bindings>(*module,
                                          ArrayAttr::get(&context, bindings));
  std::array<double, 3> samples;
  for (double &sample : samples) {
    auto start = std::chrono::steady_clock::now();
    if (failed(verify(*module)))
      return 1;
    sample = std::chrono::duration<double, std::milli>(
                 std::chrono::steady_clock::now() - start)
                 .count();
  }
  std::sort(samples.begin(), samples.end());
  llvm::outs() << "bindings=" << count << " verify_ms=" << samples[1] << '\n';
  return 0;
}

int main(int argc, char **argv) {
  MLIRContext context;
  context.disableMultithreading();
  if (argc == 3 && llvm::StringRef(argv[1]) == "--benchmark") {
    unsigned count;
    if (llvm::StringRef(argv[2]).getAsInteger(10, count) || count == 0)
      return 1;
    return benchmark(context, count);
  }
  if (argc == 3 && llvm::StringRef(argv[1]) == "--benchmark-bindings") {
    unsigned count;
    if (llvm::StringRef(argv[2]).getAsInteger(10, count) || count == 0 ||
        count > (1 << 20))
      return 1;
    return benchmarkBindings(context, count);
  }
  return apiTests(context);
}
