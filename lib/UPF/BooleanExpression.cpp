#include "BooleanExpression.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/StringExtras.h"
#include <algorithm>

using namespace mlir;
using namespace llvm;
namespace talos {
namespace {
using Opcode = upf::ExpressionOpcode;
struct Operator {
  StringLiteral spelling;
  Opcode opcode;
  unsigned precedence;
};
// IEEE 1801-2018 5.4, Table 3. Within each precedence class use the
// SystemVerilog operator ordering; match longer spellings first.
constexpr Operator operators[] = {
    {"||", Opcode::Or, 1},           {"&&", Opcode::And, 2},
    {"|", Opcode::BitOr, 3},         {"^", Opcode::BitXor, 4},
    {"&", Opcode::BitAnd, 5},        {"==", Opcode::Equal, 6},
    {"!=", Opcode::NotEqual, 6},     {"<=", Opcode::LessEqual, 7},
    {">=", Opcode::GreaterEqual, 7}, {"<", Opcode::Less, 7},
    {">", Opcode::Greater, 7}};

class Parser {
  StringRef text;
  size_t cursor = 0;
  MLIRContext *context;
  llvm::function_ref<FailureOr<upf::ExpressionTokenAttr>(StringRef)> resolve;
  llvm::function_ref<void(const Twine &)> report;
  SmallVector<Attribute> tokens;
  SmallVector<unsigned> heights;
  bool failed = false;

  bool error(const Twine &message) {
    if (!failed)
      report("UPF Boolean expression at byte " + Twine(cursor) + ": " +
             message);
    failed = true;
    return false;
  }
  void space() {
    while (cursor < text.size() && isSpace(text[cursor]))
      ++cursor;
  }
  bool append(upf::ExpressionTokenAttr token, unsigned arity = 0) {
    if (tokens.size() == 4096)
      return error("expression exceeds 4096 tokens");
    unsigned height = 0;
    for (unsigned i = 0; i < arity; ++i)
      height = std::max(height, heights.pop_back_val());
    if (++height > 256)
      return error("expression tree exceeds 256 levels");
    heights.push_back(height);
    tokens.push_back(token);
    return true;
  }
  bool operation(Opcode opcode, unsigned arity) {
    return append(upf::ExpressionTokenAttr::get(context, opcode, {}, {}, {},
                                                false, false, 1, 1, 0),
                  arity);
  }
  bool constant(StringRef spelling) {
    size_t originalQuote = spelling.find('\'');
    if (originalQuote == 0 && spelling.size() != 2)
      return error("unsized based literals require an explicit width");
    if (originalQuote != StringRef::npos && originalQuote != 0) {
      StringRef suffix = spelling.drop_front(originalQuote + 1);
      if (suffix.starts_with_insensitive("s"))
        suffix = suffix.drop_front();
      if (suffix.empty() || suffix.front() == '_' ||
          (suffix.size() > 1 && suffix[1] == '_'))
        return error("invalid underscore placement in literal");
    }
    std::string buffer;
    for (char ch : spelling)
      if (ch != '_')
        buffer.push_back(toLower(ch));
    StringRef literal(buffer);
    size_t quote = literal.find('\'');
    unsigned width = 32, radix = 10;
    bool isSigned = true, fill = false;
    StringRef digits = literal;
    if (quote == 0 && literal.size() == 2 &&
        StringRef("01xz").contains(literal[1])) {
      width = 1;
      fill = true;
      isSigned = false;
      digits = literal.drop_front();
      radix = 2;
    } else if (quote != StringRef::npos) {
      if (quote == 0)
        return error("unsized based literals require an explicit width");
      if (literal.take_front(quote).getAsInteger(10, width) || width == 0 ||
          width > 4096)
        return error("literal width must be 1..4096");
      digits = literal.drop_front(quote + 1);
      isSigned = digits.consume_front("s");
      if (digits.empty())
        return error("missing literal radix");
      switch (digits.front()) {
      case 'b':
        radix = 2;
        break;
      case 'o':
        radix = 8;
        break;
      case 'd':
        radix = 10;
        break;
      case 'h':
        radix = 16;
        break;
      default:
        return error("invalid literal radix");
      }
      digits = digits.drop_front();
    }
    if (digits.empty() || digits.size() > 4096)
      return error("literal requires 1..4096 digits");
    APInt value(width, 0), unknown(width, 0);
    auto unknownDigit = [](char ch) {
      return ch == 'x' || ch == 'z' || ch == '?';
    };
    if (radix == 10) {
      if (digits.size() == 1 && unknownDigit(digits.front())) {
        unknown.setAllBits();
        if (digits.front() != 'x')
          value.setAllBits();
      } else {
        APInt parsed;
        if (digits.getAsInteger(10, parsed))
          return error("invalid decimal literal");
        if (quote == StringRef::npos && parsed.getActiveBits() > 31)
          return error("large decimal literals require an explicit width");
        value = parsed.zextOrTrunc(width);
      }
    } else {
      unsigned bits = radix == 2 ? 1 : radix == 8 ? 3 : 4;
      for (char digit : digits) {
        value = bits >= width ? APInt(width, 0) : value.shl(bits);
        unknown = bits >= width ? APInt(width, 0) : unknown.shl(bits);
        if (unknownDigit(digit)) {
          unknown |= APInt::getLowBitsSet(width, std::min(bits, width));
          if (digit != 'x')
            value |= APInt::getLowBitsSet(width, std::min(bits, width));
        } else {
          unsigned number = hexDigitValue(digit);
          if (number >= radix)
            return error("digit is invalid for literal radix");
          // IEEE 1801-2018 5.4 inherits SV sized-literal truncation, even
          // when a single hex/octal digit exceeds the declared bit width.
          value |=
              APInt(width, number, /*isSigned=*/false, /*implicitTrunc=*/true);
        }
      }
      unsigned used = digits.size() * bits;
      // SV based literals pad an initial X/Z digit through the declared size.
      if (used < width && unknownDigit(digits.front())) {
        unknown.setBitsFrom(used);
        if (digits.front() != 'x')
          value.setBitsFrom(used);
      }
    }
    auto type = IntegerType::get(context, width);
    return append(upf::ExpressionTokenAttr::get(
        context, Opcode::Constant, {}, IntegerAttr::get(type, value),
        IntegerAttr::get(type, unknown), isSigned, fill, 1, 1, 0));
  }
  bool primary(unsigned depth) {
    if (depth > 256)
      return error("expression nesting exceeds 256 levels");
    space();
    if (cursor == text.size())
      return error("expected an operand");
    char ch = text[cursor];
    if (ch == '!' || ch == '~') {
      ++cursor;
      return primary(depth + 1) &&
             operation(ch == '!' ? Opcode::Not : Opcode::BitNot, 1);
    }
    if (ch == '(') {
      ++cursor;
      if (!expression(1, depth + 1))
        return false;
      space();
      if (cursor == text.size() || text[cursor] != ')')
        return error("expected closing parenthesis");
      ++cursor;
      return true;
    }
    size_t begin = cursor;
    if (isDigit(ch) || ch == '\'') {
      while (cursor < text.size() &&
             (isAlnum(text[cursor]) || text[cursor] == '_' ||
              text[cursor] == '\'' || text[cursor] == '?'))
        ++cursor;
      return constant(text.slice(begin, cursor));
    }
    while (cursor < text.size()) {
      // Selectors are part of the HDL object name, including their internal
      // whitespace and ':'/'+'/'-' syntax. Semantic resolution checks them.
      if (text[cursor] == '[') {
        size_t close = text.find(']', cursor + 1);
        cursor = close == StringRef::npos ? text.size() : close + 1;
        continue;
      }
      if (isSpace(text[cursor])) {
        size_t next = cursor;
        while (next < text.size() && isSpace(text[next]))
          ++next;
        if (next < text.size() && text[next] == '[') {
          cursor = next;
          continue;
        }
        break;
      }
      if (StringRef("!~<>=&^|()+*%?:,;{}").contains(text[cursor]))
        break;
      ++cursor;
    }
    if (begin == cursor)
      return error("expected a control or literal; unsupported operator");
    auto token = resolve(text.slice(begin, cursor));
    if (mlir::failed(token)) {
      failed = true;
      return false;
    }
    return append(*token);
  }
  bool expression(unsigned precedence, unsigned depth) {
    if (!primary(depth))
      return false;
    while (true) {
      space();
      const Operator *next = nullptr;
      for (auto &op : operators)
        if (text.drop_front(cursor).starts_with(op.spelling)) {
          next = &op;
          break;
        }
      if (!next || next->precedence < precedence)
        return true;
      cursor += next->spelling.size();
      if (!expression(next->precedence + 1, depth + 1) ||
          !operation(next->opcode, 2))
        return false;
    }
  }

public:
  Parser(StringRef text, MLIRContext *context,
         llvm::function_ref<FailureOr<upf::ExpressionTokenAttr>(StringRef)>
             resolve,
         llvm::function_ref<void(const Twine &)> report)
      : text(text), context(context), resolve(resolve), report(report) {}
  FailureOr<upf::ExpressionAttr> parse() {
    if (text.size() > 64 * 1024) {
      error("expression exceeds 64 KiB");
      return failure();
    }
    if (!expression(1, 1))
      return failure();
    space();
    if (cursor != text.size()) {
      error("unexpected token or unsupported operator");
      return failure();
    }
    // Validation errors must remain catchable Tcl errors (1801-2018 5.11),
    // including restrictions shared with the textual IR verifier.
    ScopedDiagnosticHandler handler(context, [&](Diagnostic &diagnostic) {
      error(diagnostic.str());
      return success();
    });
    auto result = upf::ExpressionAttr::getChecked(
        [&] { return emitError(UnknownLoc::get(context)); }, context,
        ArrayAttr::get(context, tokens));
    return result ? FailureOr<upf::ExpressionAttr>(result)
                  : FailureOr<upf::ExpressionAttr>(failure());
  }
};
} // namespace
FailureOr<upf::ExpressionAttr> parseUPFBooleanExpression(
    StringRef text, MLIRContext *context,
    llvm::function_ref<FailureOr<upf::ExpressionTokenAttr>(StringRef)> resolve,
    llvm::function_ref<void(const Twine &)> report) {
  return Parser(text, context, resolve, report).parse();
}
} // namespace talos
