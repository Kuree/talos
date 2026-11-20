#include "svdpi.h"
#include <string.h>

extern int local_id(void);
static int key;
static int values[43];

int distinct_package(void) {
  svScope pkg = svGetScope();
  svScope instance = svGetScopeFromName("top");
  const char *name = "top.declarations.with_function";
  svScope ordinary = svGetScopeFromName(name);
  svScope functions = svGetScopeFromName("functions_only");
  return pkg && instance && pkg != instance && ordinary &&
         !strcmp(svGetNameFromScope(ordinary), name) && functions &&
         !strcmp(svGetNameFromScope(functions), "functions_only") &&
         svGetScopeFromName(svGetNameFromScope(pkg)) == pkg;
}

int nested(int n) {
  svScope scope = svGetScope();
  int unit;
  if (!scope || svGetTimeUnit(scope, &unit) || unit != (n == 42 ? -8 : -9))
    return -1;
  // Change this import's selection before returning to its enclosing export.
  if (svSetScope(svGetScopeFromName("top")) != scope)
    return -1;
  return n;
}

int probe(int n, const char *name) {
  svScope original = svGetScope(), other = svGetScopeFromName("top.blk[1]");
  if (!original || original != svGetScopeFromName(name) ||
      strcmp(svGetNameFromScope(original), name) || !other ||
      svGetScopeFromName("top.no_such_block") || svGetUserData(original, &key))
    return 0;
  if (svPutUserData(original, &key, &values[n]) ||
      svPutUserData(original, NULL, &key) ||
      svGetUserData(original, NULL) != &key || local_id() != n ||
      svGetScope() != original)
    return 0;
  if (svSetScope(other) != original || local_id() != 1 ||
      svGetScope() != other || svGetUserData(other, &key) != &values[1])
    return 0;
  return svSetScope(original) == other &&
         svGetUserData(original, &key) == &values[n];
}
