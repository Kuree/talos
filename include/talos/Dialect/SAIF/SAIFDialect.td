//===- SAIFDialect.td - IEEE 1801 Annex I data ------------*- tablegen -*-===//

#ifndef TALOS_DIALECT_SAIF_SAIFDIALECT_TD
#define TALOS_DIALECT_SAIF_SAIFDIALECT_TD

include "mlir/IR/DialectBase.td"

def SAIFDialect : Dialect {
  let name = "saif";
  let cppNamespace = "::talos::saif";
  let summary = "IEEE 1801-2018 Annex I switching activity interchange";
  let description = [{
    Ordered, compiler-only data for backward SAIF activity, library forward
    directives, and RTL forward mappings. A recursive descent importer emits
    these operations directly. Verification owns record placement, header
    structure, defaults, and semantic constraints independently of the source
    parser. Conditions are typed postfix expressions; names retain component
    and bit-select boundaries after character unescaping.

    This dialect describes exchange data, not executable power intent.
    Binding and collection lower into the existing simulation machinery.
  }];
  let useDefaultAttributePrinterParser = 1;
  let usePropertiesForAttributes = 0;
}

#endif // TALOS_DIALECT_SAIF_SAIFDIALECT_TD
