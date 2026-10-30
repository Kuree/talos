#ifndef TALOS_UPF_EXPRESSIONOPERATORS_H
#define TALOS_UPF_EXPRESSIONOPERATORS_H
#include "llvm/ADT/StringRef.h"
namespace talos {
template <class Opcode> struct ExpressionOperator {
  llvm::StringLiteral spelling;
  Opcode opcode;
  unsigned precedence;
};
// IEEE 1801-2018 5.4, Table 3: SV ordering within precedence classes.
// Sharing syntax does not conflate HDL integral and UPF supply operand types.
template <class Opcode>
inline constexpr ExpressionOperator<Opcode> expressionOperators[] = {
    {"||", Opcode::Or, 1},           {"&&", Opcode::And, 2},
    {"|", Opcode::BitOr, 3},         {"^", Opcode::BitXor, 4},
    {"&", Opcode::BitAnd, 5},        {"==", Opcode::Equal, 6},
    {"!=", Opcode::NotEqual, 6},     {"<=", Opcode::LessEqual, 7},
    {">=", Opcode::GreaterEqual, 7}, {"<", Opcode::Less, 7},
    {">", Opcode::Greater, 7}};
} // namespace talos
#endif
