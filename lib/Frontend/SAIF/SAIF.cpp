//===- SAIF.cpp - Recursive descent directly into the SAIF dialect -------===//

#include "talos/Frontend/SAIF.h"

#include "talos/Dialect/SAIF/SAIFOps.h"

#include "mlir/IR/Verifier.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSwitch.h"

#include <optional>

using namespace mlir;
using llvm::all_of;
using llvm::isAlnum;
using llvm::isAlpha;
using llvm::isDigit;
using llvm::isSpace;

namespace talos::frontend {
namespace {
using namespace talos::saif;

enum class TokenKind {
  End,
  Invalid,
  Left,
  Right,
  String,
  Identifier,
  Number,
  Dot,
  Slash,
  LeftBracket,
  RightBracket,
  Not,
  And,
  Xor,
  Or
};

struct Token {
  TokenKind kind = TokenKind::End;
  StringRef text;
  unsigned line = 1;
  unsigned column = 1;
};

class Parser {
public:
  Parser(StringRef source, StringRef input, MLIRContext &context,
         const SAIFResourceLimits &limits)
      : source(source), input(input), context(context), limits(limits),
        builder(&context) {}

  FailureOr<OwningOpRef<mlir::ModuleOp>> parse() {
    if (input.size() > limits.maxInputBytes) {
      (void)syntax(Token{}, "input exceeds the SAIF byte limit");
      return failure();
    }
    token = lex();
    next = lex();
    if (token.kind != TokenKind::Left || !is(next, "SAIFILE")) {
      (void)syntax(token, "expected '(SAIFILE'");
      return failure();
    }
    OwningOpRef<mlir::ModuleOp> module =
        mlir::ModuleOp::create(location(token));
    builder.setInsertionPointToStart(module->getBody());
    if (failed(record(0)))
      return failure();
    if (token.kind != TokenKind::End)
      (void)syntax(token, "unexpected text after SAIFILE");
    if (hadError)
      return failure();
    return std::move(module);
  }

private:
  Location location(const Token &at) {
    return FileLineColLoc::get(&context, source, at.line, at.column);
  }

  LogicalResult syntax(const Token &at, const Twine &message) {
    if (!hadError)
      emitError(location(at)) << "SAIF syntax: " << message;
    hadError = true;
    return failure();
  }

  char peek(size_t offset = 0) const {
    return cursor + offset < input.size() ? input[cursor + offset] : '\0';
  }

  char consume() {
    char result = input[cursor++];
    if (result == '\n') {
      ++line;
      column = 1;
    } else {
      ++column;
    }
    return result;
  }

  Token lex() {
    while (cursor < input.size()) {
      if (isSpace(peek())) {
        consume();
        continue;
      }
      if (peek() == '/' && peek(1) == '/') {
        while (cursor < input.size() && consume() != '\n')
          ;
        continue;
      }
      if (peek() == '/' && peek(1) == '*') {
        Token start{TokenKind::Invalid, {}, line, column};
        consume();
        consume();
        while (cursor < input.size() && !(peek() == '*' && peek(1) == '/'))
          consume();
        if (cursor == input.size()) {
          (void)syntax(start, "unterminated block comment");
          return start;
        }
        consume();
        consume();
        continue;
      }
      break;
    }
    Token result{TokenKind::End, {}, line, column};
    if (cursor == input.size())
      return result;
    size_t start = cursor;
    char c = consume();
    switch (c) {
    case '(':
      result.kind = TokenKind::Left;
      break;
    case ')':
      result.kind = TokenKind::Right;
      break;
    case '[':
      result.kind = TokenKind::LeftBracket;
      break;
    case ']':
      result.kind = TokenKind::RightBracket;
      break;
    case '!':
      result.kind = TokenKind::Not;
      break;
    case '*':
      result.kind = TokenKind::And;
      break;
    case '^':
      result.kind = TokenKind::Xor;
      break;
    case '|':
      result.kind = TokenKind::Or;
      break;
    case '/':
      result.kind = TokenKind::Slash;
      break;
    case '.':
      if (!isDigit(peek())) {
        result.kind = TokenKind::Dot;
        break;
      }
      [[fallthrough]];
    default:
      if (isDigit(c) || (c == '.' && isDigit(peek()))) {
        result.kind = TokenKind::Number;
        while (isDigit(peek()))
          consume();
        if (c != '.' && peek() == '.') {
          consume();
          while (isDigit(peek()))
            consume();
        }
        if (peek() == 'e' || peek() == 'E') {
          consume();
          if (peek() == '+' || peek() == '-')
            consume();
          if (!isDigit(peek())) {
            (void)syntax(result, "expected exponent digits");
            result.kind = TokenKind::Invalid;
          }
          while (isDigit(peek()))
            consume();
        }
      } else if (isAlpha(c) || c == '_' || c == '\\') {
        result.kind = TokenKind::Identifier;
        if (c == '\\') {
          if (cursor == input.size() || isSpace(peek())) {
            (void)syntax(result, "escape requires a non-whitespace character");
            result.kind = TokenKind::Invalid;
          } else {
            consume();
          }
        }
        while (isAlnum(peek()) || peek() == '_' || peek() == '\\') {
          if (consume() == '\\') {
            if (cursor == input.size() || isSpace(peek())) {
              (void)syntax(result,
                           "escape requires a non-whitespace character");
              result.kind = TokenKind::Invalid;
              break;
            }
            consume();
          }
        }
      } else {
        result.kind = TokenKind::Invalid;
        (void)syntax(result, "unexpected character");
      }
      break;
    case '"':
      result.kind = TokenKind::String;
      start = cursor;
      while (cursor < input.size() && peek() != '"' && peek() != '\n' &&
             peek() != '\r' && peek() != '\0')
        consume();
      result.text = input.slice(start, cursor);
      if (cursor == input.size() || peek() != '"') {
        (void)syntax(result, "unterminated single-line string");
        result.kind = TokenKind::Invalid;
      } else {
        consume();
      }
      return result;
    }
    result.text = input.slice(start, cursor);
    return result;
  }

  static bool is(const Token &at, StringRef keyword) {
    return at.kind == TokenKind::Identifier && at.text == keyword;
  }

  void advance() {
    token = next;
    next = lex();
  }

  LogicalResult expect(TokenKind kind, StringRef description) {
    if (hadError)
      return failure();
    if (token.kind != kind)
      return syntax(token, Twine("expected ") + description);
    advance();
    return success();
  }

  template <typename Op>
  Op make(const Token &at, const NamedAttrList &attrs = {}, bool body = false) {
    if (hadError)
      return {};
    if (++operations > limits.maxOperations) {
      (void)syntax(at, "operation count exceeds the SAIF resource limit");
      return {};
    }
    OperationState state(location(at), Op::getOperationName());
    state.addAttributes(attrs);
    if (body)
      state.addRegion();
    Op op = cast<Op>(builder.create(state));
    if (body)
      op->getRegion(0).emplaceBlock();
    return op;
  }

  StringAttr string() {
    if (token.kind != TokenKind::String) {
      (void)syntax(token, "expected a quoted string");
      return {};
    }
    auto result = builder.getStringAttr(token.text);
    advance();
    return result;
  }

  NumberAttr number(bool integer = false) {
    if (token.kind != TokenKind::Number ||
        (integer && !all_of(token.text, [](char c) { return isDigit(c); }))) {
      (void)syntax(token, integer ? "expected a decimal integer"
                                  : "expected a number");
      return {};
    }
    auto result = NumberAttr::get(&context, builder.getStringAttr(token.text));
    advance();
    return result;
  }

  IdentifierAttr identifier() {
    if (token.kind != TokenKind::Identifier) {
      (void)syntax(token, "expected an identifier");
      return {};
    }
    std::string name;
    for (size_t i = 0; i < token.text.size(); ++i) {
      if (token.text[i] == '\\')
        ++i;
      name.push_back(token.text[i]);
    }
    advance();
    StringAttr index;
    if (token.kind == TokenKind::LeftBracket) {
      advance();
      auto value = number(/*integer=*/true);
      if (!value)
        return {};
      StringRef spelling = value.getSpelling().getValue().ltrim('0');
      index = builder.getStringAttr(spelling.empty() ? "0" : spelling);
      if (failed(expect(TokenKind::RightBracket, "']'")))
        return {};
    }
    return IdentifierAttr::get(&context, builder.getStringAttr(name), index);
  }

  PathAttr path() {
    SmallVector<Attribute> components;
    auto part = identifier();
    if (!part)
      return {};
    components.push_back(part);
    TokenKind separator = divider == '/' ? TokenKind::Slash : TokenKind::Dot;
    while (token.kind == separator) {
      advance();
      part = identifier();
      if (!part)
        return {};
      components.push_back(part);
    }
    return PathAttr::get(&context, builder.getArrayAttr(components));
  }

  // Conditions use actual recursive descent, not a token string or a generic
  // S-expression tree. Postfix tokens are emitted in precedence order.
  LogicalResult condition(SmallVectorImpl<Attribute> &tokens, unsigned level,
                          unsigned depth) {
    if (depth > limits.maxNestingDepth)
      return syntax(token, "condition nesting exceeds the SAIF resource limit");
    if (level == 3) {
      if (token.kind == TokenKind::Not) {
        Token at = token;
        advance();
        if (failed(condition(tokens, level, depth + 1)))
          return failure();
        return conditionToken(tokens, at, ConditionOpcode::Not);
      }
      if (token.kind == TokenKind::Left) {
        advance();
        if (failed(condition(tokens, 0, depth + 1)))
          return failure();
        return expect(TokenKind::Right, "')' after condition");
      }
      Token at = token;
      auto pin = identifier();
      if (!pin)
        return failure();
      return conditionToken(tokens, at, ConditionOpcode::Pin, pin);
    }
    if (failed(condition(tokens, level + 1, depth)))
      return failure();
    constexpr TokenKind kinds[] = {TokenKind::Or, TokenKind::Xor,
                                   TokenKind::And};
    constexpr ConditionOpcode opcodes[] = {
        ConditionOpcode::Or, ConditionOpcode::Xor, ConditionOpcode::And};
    while (token.kind == kinds[level]) {
      Token at = token;
      advance();
      if (failed(condition(tokens, level + 1, depth)) ||
          failed(conditionToken(tokens, at, opcodes[level])))
        return failure();
    }
    return success();
  }

  LogicalResult conditionToken(SmallVectorImpl<Attribute> &tokens,
                               const Token &at, ConditionOpcode opcode,
                               IdentifierAttr pin = {}) {
    if (tokens.size() >= limits.maxConditionTokens)
      return syntax(at, "condition exceeds the SAIF token limit");
    tokens.push_back(ConditionTokenAttr::get(&context, opcode, pin));
    return success();
  }

  template <typename Op>
  LogicalResult container(const Token &at, const NamedAttrList &attrs,
                          unsigned depth) {
    auto op = make<Op>(at, attrs, /*body=*/true);
    if (!op)
      return failure();
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToStart(&op.getBody().front());
    while (token.kind == TokenKind::Left)
      if (failed(record(depth + 1)))
        return failure();
    return expect(TokenKind::Right, "')' after record");
  }

  LogicalResult header(const Token &at, HeaderKind kind) {
    NamedAttrList attrs;
    attrs.set("kind", builder.getI32IntegerAttr(static_cast<int32_t>(kind)));
    if (kind == HeaderKind::TimeScale) {
      auto amount = NumberAttr::get(&context, builder.getStringAttr("1"));
      auto unit = builder.getStringAttr("ns");
      if (token.kind != TokenKind::Right) {
        amount = number(/*integer=*/true);
        if (!amount)
          return failure();
        if (token.kind != TokenKind::Identifier)
          return syntax(token, "expected a time unit");
        unit = builder.getStringAttr(token.text);
        advance();
      }
      attrs.set("scale", TimeScaleAttr::get(&context, amount, unit));
    } else if (kind == HeaderKind::Duration) {
      auto value = number();
      if (!value)
        return failure();
      attrs.set("value", value);
    } else if (kind == HeaderKind::Divider) {
      StringRef value = ".";
      if (token.kind != TokenKind::Right) {
        if (token.kind != TokenKind::Dot && token.kind != TokenKind::Slash &&
            token.kind != TokenKind::Identifier &&
            token.kind != TokenKind::Number)
          return syntax(token, "expected a divider character");
        value = token.text;
        advance();
      }
      if (value == "/" || value == ".")
        divider = value.front();
      attrs.set("text", builder.getStringAttr(value));
    } else {
      if (kind == HeaderKind::Version || kind == HeaderKind::Direction ||
          token.kind != TokenKind::Right) {
        auto text = string();
        if (!text)
          return failure();
        attrs.set("text", text);
      }
      if (kind == HeaderKind::Version && token.kind == TokenKind::String)
        attrs.set("qualifier", string());
    }
    if (!make<HeaderOp>(at, attrs))
      return failure();
    return expect(TokenKind::Right, "')' after header");
  }

  LogicalResult entries(const Token &at, bool port, unsigned depth) {
    if (port && token.kind == TokenKind::Identifier) {
      NamedAttrList attrs;
      auto name = path();
      if (!name)
        return failure();
      attrs.set("name", name);
      return container<PortDirectiveOp>(at, attrs, depth);
    }
    // IEEE 1801-2018 I.4.8: Syntax 37 reads (PORT port_name {port_directive}),
    // while the clause's example groups pins as (PORT (A ...) (B ...)). Accept
    // both in a library cell; each group is one port declaration.
    if (port && token.kind == TokenKind::Left &&
        isa_and_nonnull<CellOp>(builder.getInsertionBlock()->getParentOp())) {
      while (token.kind == TokenKind::Left) {
        Token start = token;
        advance();
        NamedAttrList attrs;
        auto name = path();
        if (!name)
          return failure();
        attrs.set("name", name);
        if (failed(container<PortDirectiveOp>(start, attrs, depth + 1)))
          return failure();
      }
      return expect(TokenKind::Right, "')' after PORT");
    }
    Operation *op = port ? make<PortsOp>(at, {}, true).getOperation()
                         : make<NetsOp>(at, {}, true).getOperation();
    if (!op)
      return failure();
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToStart(&op->getRegion(0).front());
    while (token.kind == TokenKind::Left) {
      Token start = token;
      advance();
      auto name = path();
      if (!name)
        return failure();
      NamedAttrList attrs;
      if (token.kind == TokenKind::Identifier) {
        auto mapped = path();
        if (!mapped)
          return failure();
        attrs.set("source_name", name);
        attrs.set("mapped_name", mapped);
        if (token.kind == TokenKind::String)
          attrs.set("virtual_type", string());
        if (!make<MappingOp>(start, attrs) ||
            failed(expect(TokenKind::Right, "')' after name mapping")))
          return failure();
      } else {
        attrs.set("name", name);
        if (failed(container<SignalOp>(start, attrs, depth + 1)))
          return failure();
      }
    }
    return expect(TokenKind::Right, "')' after PORT or NET");
  }

  LogicalResult conditions(const Token &at, unsigned depth) {
    auto group = make<ConditionsOp>(at, {}, true);
    if (!group)
      return failure();
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToStart(&group.getBody().front());
    while (is(token, "COND") || is(token, "COND_DEFAULT")) {
      Token start = token;
      bool fallback = is(token, "COND_DEFAULT");
      advance();
      NamedAttrList attrs;
      if (!fallback) {
        SmallVector<Attribute> tokens;
        if (failed(condition(tokens, 0, 0)))
          return failure();
        attrs.set("condition",
                  ConditionAttr::get(&context, builder.getArrayAttr(tokens)));
      }
      Edge edge = Edge::None;
      if (is(token, "RISE_FALL")) {
        edge = Edge::RiseFall;
        advance();
      } else if (token.kind == TokenKind::Left &&
                 (is(next, "RISE") || is(next, "FALL"))) {
        advance();
        edge = is(token, "RISE") ? Edge::Rise : Edge::Fall;
        advance();
        if (failed(expect(TokenKind::Right, "')' after edge restriction")))
          return failure();
      }
      attrs.set("edge", builder.getI32IntegerAttr(static_cast<int32_t>(edge)));
      auto when = make<WhenOp>(start, attrs, true);
      if (!when)
        return failure();
      {
        OpBuilder::InsertionGuard itemGuard(builder);
        builder.setInsertionPointToStart(&when.getBody().front());
        while (token.kind == TokenKind::Left)
          if (failed(record(depth + 1)))
            return failure();
      }
    }
    return expect(TokenKind::Right, "')' after condition group");
  }

  LogicalResult paths(const Token &at, unsigned depth) {
    auto group = make<PathsOp>(at, {}, true);
    if (!group)
      return failure();
    OpBuilder::InsertionGuard guard(builder);
    builder.setInsertionPointToStart(&group.getBody().front());
    while (is(token, "IOPATH") || is(token, "IOPATH_DEFAULT")) {
      Token start = token;
      bool fallback = is(token, "IOPATH_DEFAULT");
      advance();
      SmallVector<Attribute> pins;
      while (token.kind == TokenKind::Identifier && !is(token, "IOPATH") &&
             !is(token, "IOPATH_DEFAULT")) {
        auto pin = identifier();
        if (!pin)
          return failure();
        pins.push_back(pin);
      }
      NamedAttrList attrs;
      attrs.set("pins", builder.getArrayAttr(pins));
      attrs.set("is_default", builder.getBoolAttr(fallback));
      auto path = make<PathOp>(start, attrs, true);
      if (!path)
        return failure();
      {
        OpBuilder::InsertionGuard itemGuard(builder);
        builder.setInsertionPointToStart(&path.getBody().front());
        while (token.kind == TokenKind::Left)
          if (failed(record(depth + 1)))
            return failure();
      }
    }
    return expect(TokenKind::Right, "')' after path group");
  }

  LogicalResult record(unsigned depth) {
    if (depth > limits.maxNestingDepth)
      return syntax(token, "record nesting exceeds the SAIF resource limit");
    Token at = token;
    if (failed(expect(TokenKind::Left, "'('")))
      return failure();
    Token head = token;
    if (head.kind != TokenKind::Identifier)
      return syntax(head, "expected a record keyword");
    // COND and IOPATH introduce unparenthesized items inside one list.
    if (is(head, "COND") || is(head, "COND_DEFAULT"))
      return conditions(at, depth);
    if (is(head, "IOPATH") || is(head, "IOPATH_DEFAULT"))
      return paths(at, depth);
    advance();
    auto headerKind = StringSwitch<std::optional<HeaderKind>>(head.text)
                          .Case("SAIFVERSION", HeaderKind::Version)
                          .Case("DIRECTION", HeaderKind::Direction)
                          .Case("DESIGN", HeaderKind::Design)
                          .Case("DATE", HeaderKind::Date)
                          .Case("VENDOR", HeaderKind::Vendor)
                          .Case("PROGRAM_NAME", HeaderKind::ProgramName)
                          .Case("PROGRAM_VERSION", HeaderKind::ProgramVersion)
                          .Case("DIVIDER", HeaderKind::Divider)
                          .Case("TIMESCALE", HeaderKind::TimeScale)
                          .Case("DURATION", HeaderKind::Duration)
                          .Default(std::nullopt);
    if (headerKind)
      return header(at, *headerKind);
    if (auto metric = symbolizeMetricKind(head.text)) {
      auto value = number();
      if (!value)
        return failure();
      NamedAttrList attrs;
      attrs.set("kind",
                builder.getI32IntegerAttr(static_cast<int32_t>(*metric)));
      attrs.set("value", value);
      if (!make<MetricOp>(at, attrs))
        return failure();
      return expect(TokenKind::Right, "')' after metric");
    }
    NamedAttrList attrs;
    if (head.text == "SAIFILE") {
      attrs.set("source", builder.getStringAttr(source));
      return container<FileOp>(at, attrs, depth);
    }
    if (head.text == "INSTANCE" || head.text == "VIRTUAL_INSTANCE") {
      if (token.kind == TokenKind::String)
        attrs.set("cell", string());
      auto name = path();
      if (!name)
        return failure();
      attrs.set("name", name);
      attrs.set("is_virtual",
                builder.getBoolAttr(head.text == "VIRTUAL_INSTANCE"));
      return container<InstanceOp>(at, attrs, depth);
    }
    if (head.text == "LIBRARY") {
      auto name = string();
      if (!name)
        return failure();
      attrs.set("name", name);
      if (token.kind == TokenKind::String)
        attrs.set("directory", string());
      return container<LibraryOp>(at, attrs, depth);
    }
    if (head.text == "MODULE") {
      auto name = path();
      if (!name)
        return failure();
      attrs.set("name", name);
      return container<CellOp>(at, attrs, depth);
    }
    if (head.text == "PORT" || head.text == "NET")
      return entries(at, head.text == "PORT", depth);
    if (head.text == "LEAKAGE")
      return container<LeakageOp>(at, attrs, depth);
    return syntax(head, Twine("unknown record keyword '") + head.text + "'");
  }

  StringRef source;
  StringRef input;
  MLIRContext &context;
  const SAIFResourceLimits &limits;
  OpBuilder builder;
  Token token;
  Token next;
  size_t cursor = 0;
  uint64_t operations = 0;
  unsigned line = 1;
  unsigned column = 1;
  char divider = '.';
  bool hadError = false;
};
} // namespace

FailureOr<OwningOpRef<mlir::ModuleOp>>
importSAIF(StringRef sourceName, StringRef contents, MLIRContext &context,
           bool verifyIR, const SAIFResourceLimits &limits) {
  context.getOrLoadDialect<saif::SAIFDialect>();
  auto module = Parser(sourceName, contents, context, limits).parse();
  if (failed(module))
    return failure();
  if (verifyIR && failed(mlir::verify(**module)))
    return failure();
  return std::move(*module);
}

} // namespace talos::frontend
