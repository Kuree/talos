//===- talos-translate.cpp - Talos source translators ---------------===//

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "talos/Dialect/Coverage/CoverageDialect.h"
#include "talos/Dialect/DPI/DPIDialect.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/SAIF/SAIFDialect.h"
#include "talos/Dialect/SDF/SDFDialect.h"
#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Frontend/SAIF.h"
#include "talos/Frontend/SDF.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/Tools/mlir-translate/MlirTranslateMain.h"
#include "mlir/Tools/mlir-translate/Translation.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/SourceMgr.h"

using namespace mlir;

// Lets tests reach the importer's input-size limit with a small file.
static llvm::cl::opt<uint64_t> sdfMaxInputBytes(
    "sdf-max-input-bytes", llvm::cl::ReallyHidden,
    llvm::cl::desc("Largest SDF input --import-sdf accepts"),
    llvm::cl::init(talos::frontend::SDFResourceLimits().maxFileBytes));

static llvm::cl::opt<uint64_t> saifMaxInputBytes(
    "saif-max-input-bytes", llvm::cl::ReallyHidden,
    llvm::cl::desc("Largest SAIF input --import-saif accepts"),
    llvm::cl::init(talos::frontend::SAIFResourceLimits().maxInputBytes));

static llvm::cl::opt<bool> saifVerify(
    "saif-verify", llvm::cl::ReallyHidden,
    llvm::cl::desc(
        "Verify imported SAIF data (disable to inspect illegal data)"),
    llvm::cl::init(true));

int main(int argc, char **argv) {
  TranslateFromMLIRRegistration exportLLVM(
      "mlir-to-llvmir",
      "translate LLVM dialect IR with typed Talos backend metadata",
      [](Operation *operation, llvm::raw_ostream &output) {
        llvm::LLVMContext context;
        auto module = translateModuleToLLVMIR(operation, context);
        if (!module)
          return failure();
        module->print(output, nullptr);
        return success();
      },
      [](DialectRegistry &registry) {
        registry.insert<LLVM::LLVMDialect, talos::cov::CoverageDialect,
                        talos::dpi::DPIDialect, talos::native::NativeDialect,
                        talos::runtime::TalosRuntimeDialect,
                        talos::schedule::ScheduleDialect>();
        registerBuiltinDialectTranslation(registry);
        registerLLVMDialectTranslation(registry);
      });

  TranslateToMLIRRegistration importSDF(
      "import-sdf", "import an IEEE 1800-2017 Clause 32 SDF delay file",
      [](llvm::SourceMgr &sourceMgr,
         MLIRContext *context) -> OwningOpRef<Operation *> {
        const llvm::MemoryBuffer *buffer = sourceMgr.getMemoryBuffer(1);
        auto module = talos::frontend::importSDF(
            buffer->getBufferIdentifier(), buffer->getBuffer(), *context,
            /*verifyIR=*/true, sdfMaxInputBytes);
        if (failed(module))
          return {};
        return OwningOpRef<Operation *>((*module).release().getOperation());
      },
      [](DialectRegistry &registry) {
        registry.insert<talos::sdf::TalosSDFDialect>();
      });

  // Unlike TranslateToMLIRRegistration, this does not implicitly verify the
  // module a second time or prevent syntax-only inspection of illegal data.
  TranslateRegistration importSAIF(
      "import-saif", "import IEEE 1801-2018 Annex I SAIF data",
      [](const std::shared_ptr<llvm::SourceMgr> &sourceMgr,
         llvm::raw_ostream &output, MLIRContext *context) -> LogicalResult {
        const llvm::MemoryBuffer *buffer = sourceMgr->getMemoryBuffer(1);
        talos::frontend::SAIFResourceLimits limits;
        limits.maxInputBytes = saifMaxInputBytes;
        auto module = talos::frontend::importSAIF(buffer->getBufferIdentifier(),
                                                  buffer->getBuffer(), *context,
                                                  saifVerify, limits);
        if (failed(module))
          return failure();
        (*module)->print(output);
        output << '\n';
        return success();
      });

  return failed(mlirTranslateMain(argc, argv, "Talos translation driver"));
}
