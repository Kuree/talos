// Keep each bounded SAT query and its model read in the same Z3 context.
#include <string>
#include <z3.h>
#if defined(_WIN32)
#define RANK_API extern "C" __declspec(dllexport)
#else
#define RANK_API extern "C" __attribute__((visibility("default")))
#endif
namespace {
struct Session {
  Z3_context context;
  std::string output;

  Session() {
    auto config = Z3_mk_config();
    context = Z3_mk_context(config);
    Z3_del_config(config);
    Z3_set_error_handler(context, [](Z3_context, Z3_error_code) {});
  }
  ~Session() { Z3_del_context(context); }
};
} // namespace

RANK_API void *talos_rank_solver() { return new Session(); }
RANK_API void talos_rank_solver_free(Session *session) { delete session; }
RANK_API const char *talos_rank_smt(Session *session, const char *query,
                                    const char *values) {
  session->output = Z3_eval_smtlib2_string(session->context, query);
  if (session->output == "sat\n" && *values)
    session->output += Z3_eval_smtlib2_string(session->context, values);
  return session->output.c_str();
}
