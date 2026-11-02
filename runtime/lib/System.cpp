//===- System.cpp - Host command execution (IEEE 1800 20.18) ------------===//

#include "RuntimeInternal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <process.h>
#include <stdlib.h>
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif
#if defined(__APPLE__)
#include <crt_externs.h>
#include <mach-o/dyld.h>
#endif

namespace {

// IEEE 1800-2023 Annex D tasks that act on the tool itself reach the runtime as
// a command starting with a NUL, which no SystemVerilog string holds (6.16), so
// this adds no operation and no cost to a design that does not use them. The
// task name and its arguments follow, separated by NULs.
std::vector<std::string_view> splitControl(std::string_view text) {
  std::vector<std::string_view> parts;
  while (true) {
    size_t end = text.find('\0');
    parts.push_back(text.substr(0, end));
    if (end == std::string_view::npos)
      return parts;
    text.remove_prefix(end + 1);
  }
}

talos_rt_status printText(talos_rt_context *context, std::string_view text) {
  return writeUnlocked(context, 1, text.data(), text.size(), nullptr);
}

const char *const kResetCountVariable = "TALOS_RESET_COUNT";
const char *const kResetValueVariable = "TALOS_RESET_VALUE";

int32_t environmentInteger(const char *name) {
  const char *value = std::getenv(name);
  return value ? static_cast<int32_t>(std::strtol(value, nullptr, 10)) : 0;
}

void setEnvironment(const char *name, const std::string &value) {
#if defined(_WIN32)
  // The C runtime's copy for getenv, and the process's for a child it creates.
  _putenv_s(name, value.c_str());
  SetEnvironmentVariableA(name, value.c_str());
#else
  setenv(name, value.c_str(), 1);
#endif
}

// IEEE 1800-2023 D.8: "The simulation time is 0. All variables and nets contain
// their initial values" and every procedure starts again, which running the
// executable again with its own arguments provides exactly. A compiled
// simulation has no interactive mode for a stop_value of 0 to enter, so
// processing always begins again at once. Only the reset count and value cross
// the reset.
talos_rt_status resetToTimeZero(talos_rt_context *context, std::string_view value) {
  setEnvironment(kResetCountVariable,
                 std::to_string(environmentInteger(kResetCountVariable) + 1));
  setEnvironment(kResetValueVariable, std::string(value));
  std::fflush(nullptr);
#if defined(__EMSCRIPTEN__)
  setLastError(context, "$reset is not available on this platform");
  return TALOS_RT_INVALID_ARGUMENT;
#elif defined(_WIN32)
  // Windows has no exec that keeps the process: _execv ends this one at once,
  // so a shell or pipe waiting on it would move on without the restarted run.
  // Run the executable again with its own command line, wait for it, and end
  // with its status.
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = 0;
  while ((length = GetModuleFileNameW(nullptr, path.data(),
                                      static_cast<DWORD>(path.size()))) ==
         path.size())
    path.resize(path.size() * 2);
  path.resize(length);
  std::wstring commandLine = GetCommandLineW();
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION process{};
  if (length != 0 &&
      CreateProcessW(path.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
                     0, nullptr, nullptr, &startup, &process)) {
    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD status = 1;
    GetExitCodeProcess(process.hProcess, &status);
    CloseHandle(process.hProcess);
    _exit(static_cast<int>(status));
  }
#elif defined(__APPLE__)
  char path[4096];
  uint32_t size = sizeof(path);
  if (_NSGetExecutablePath(path, &size) == 0)
    execv(path, *_NSGetArgv());
#else
  std::ifstream commandLine("/proc/self/cmdline", std::ios::binary);
  std::string arguments((std::istreambuf_iterator<char>(commandLine)),
                        std::istreambuf_iterator<char>());
  std::vector<char *> argv;
  for (size_t offset = 0; offset < arguments.size();
       offset += std::strlen(arguments.data() + offset) + 1)
    argv.push_back(arguments.data() + offset);
  argv.push_back(nullptr);
  execv("/proc/self/exe", argv.data());
#endif
  setLastError(context, "$reset could not restart the executable");
  return TALOS_RT_IO_ERROR;
}

// IEEE 1800-2023 D.7: "An optional file name argument for $log causes the old
// file to be closed, a new log file to be created, and output to be directed to
// the new log file."
talos_rt_status controlLog(talos_rt_context *context, std::string_view path) {
  context->logPaused = false;
  if (path.empty())
    return TALOS_RT_OK;
  if (context->logFile)
    std::fclose(context->logFile);
  context->logFile = std::fopen(std::string(path).c_str(), "w");
  if (context->logFile)
    return TALOS_RT_OK;
  setLastError(context, "$log could not create its file");
  return TALOS_RT_IO_ERROR;
}

// The string literal argument of a one-argument command, with its escapes.
bool parseStringCommand(std::string_view line, std::string_view name,
                        std::string &text) {
  if (line.substr(0, name.size()) != name)
    return false;
  line.remove_prefix(name.size());
  size_t open = line.find('"');
  size_t close = line.rfind('"');
  if (open == std::string_view::npos || close <= open ||
      line.substr(0, open).find_first_not_of(" \t(") != std::string_view::npos ||
      line.substr(close + 1).find_first_not_of(" \t);") != std::string_view::npos)
    return false;
  for (size_t index = open + 1; index < close; ++index) {
    char character = line[index];
    if (character == '\\' && index + 1 < close) {
      char escaped = line[++index];
      character = escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped;
    }
    text.push_back(character);
  }
  return true;
}

// IEEE 1800-2023 D.4: "$input allows command input text to come from a named
// file instead of from the terminal", after which input returns to the terminal.
// A compiled simulation has no terminal command language, so the file may hold
// the commands that need no compiler, one per line: $display and $write of a
// string literal, $input, and comments. Anything else is reported and skipped.
talos_rt_status runCommandFile(talos_rt_context *context, const std::string &path,
                               unsigned depth) {
  std::ifstream file(path);
  if (!file || depth > 16) {
    std::fprintf(stderr, "warning: $input cannot read command file '%s'\n",
                 path.c_str());
    return TALOS_RT_OK;
  }
  std::string line;
  while (std::getline(file, line)) {
    std::string_view command(line);
    size_t first = command.find_first_not_of(" \t\r");
    if (first == std::string_view::npos ||
        command.substr(first, 2) == "//")
      continue;
    command.remove_prefix(first);
    while (!command.empty() && (command.back() == '\r' || command.back() == ' '))
      command.remove_suffix(1);
    std::string text;
    if (parseStringCommand(command, "$display", text)) {
      text.push_back('\n');
      if (talos_rt_status status = printText(context, text);
          status != TALOS_RT_OK)
        return status;
    } else if (parseStringCommand(command, "$write", text)) {
      if (talos_rt_status status = printText(context, text);
          status != TALOS_RT_OK)
        return status;
    } else if (parseStringCommand(command, "$input", text)) {
      if (talos_rt_status status = runCommandFile(context, text, depth + 1);
          status != TALOS_RT_OK)
        return status;
    } else {
      std::fprintf(stderr,
                   "warning: $input skipped a command a compiled simulation "
                   "cannot run: %s\n",
                   line.c_str());
    }
  }
  return TALOS_RT_OK;
}

std::string currentInteractiveScope(talos_rt_context *context) {
  return context->interactiveScope.empty()
             ? talos_rt_interactive_first_scope(context)
             : context->interactiveScope;
}

// IEEE 1800-2023 D.12: the objects "at the current scope level", or with a
// nonzero argument those "in or below the current hierarchical scope". The
// compiler lists every object as a parent path and a name, top levels first.
talos_rt_status showScopes(talos_rt_context *context, bool below,
                           const std::vector<std::string_view> &parts) {
  std::string scope = context->interactiveScope;
  if (scope.empty() && parts.size() > 3)
    scope = std::string(parts[3]);
  std::string listing;
  std::string nested = scope + ".";
  for (size_t index = 2; index + 1 < parts.size(); index += 2) {
    std::string_view parent = parts[index];
    if (parent == scope) {
      listing.append(parts[index + 1]);
      listing.push_back('\n');
    } else if (below && parent.substr(0, nested.size()) == nested) {
      listing.append(parent.substr(nested.size()));
      listing.push_back('.');
      listing.append(parts[index + 1]);
      listing.push_back('\n');
    }
  }
  return printText(context, listing);
}

talos_rt_status runControl(talos_rt_context *context, std::string_view control,
                           int32_t &result) {
  std::vector<std::string_view> parts = splitControl(control);
  std::string_view task = parts.front();
  auto argument = [&](size_t index) {
    return index < parts.size() ? parts[index] : std::string_view{};
  };
  result = 0;
  std::lock_guard<std::recursive_mutex> lock(context->mutex);
  if (task == "log")
    return controlLog(context, argument(1));
  if (task == "nolog") {
    context->logPaused = true;
    return TALOS_RT_OK;
  }
  if (task == "reset")
    return resetToTimeZero(context, argument(1));
  if (task == "reset_count") {
    result = environmentInteger(kResetCountVariable);
    return TALOS_RT_OK;
  }
  if (task == "reset_value") {
    result = environmentInteger(kResetValueVariable);
    return TALOS_RT_OK;
  }
  if (task == "input")
    return runCommandFile(context, std::string(argument(1)), 0);
  if (task == "scope") {
    context->interactiveScope = std::string(argument(1));
    return TALOS_RT_OK;
  }
  if (task == "showscopes")
    return showScopes(context, argument(1) != "0", parts);
  if (task == "showvars") {
    std::vector<std::string> paths;
    if (parts.size() > 1) {
      paths.assign(parts.begin() + 1, parts.end());
    } else if (talos_rt_status status = talos_rt_interactive_scope_objects(
                   context, currentInteractiveScope(context), paths);
               status != TALOS_RT_OK) {
      return status;
    }
    return talos_rt_interactive_show_vars(context, paths);
  }
  if (task == "list") {
    // The text of one named object, or of the interactive scope among the
    // objects the compiler listed as path and text pairs, top levels first.
    if (parts.size() == 2)
      return printText(context, std::string(argument(1)) + "\n");
    std::string_view scope = context->interactiveScope;
    if (scope.empty())
      scope = argument(1);
    for (size_t index = 1; index + 1 < parts.size(); index += 2)
      if (parts[index] == scope)
        return printText(context, std::string(parts[index + 1]) + "\n");
    return TALOS_RT_OK;
  }
  setLastError(context, "unknown runtime control task");
  return TALOS_RT_INVALID_ARGUMENT;
}

} // namespace

extern "C" talos_rt_status talos_rt_v1_system(talos_rt_context *context,
                                              talos_rt_string_v1 command,
                                              int32_t *outStatus) {
  if (!context || !outStatus)
    return TALOS_RT_INVALID_ARGUMENT;
  *outStatus = -1;

  char scratch[8] = {};
  const char *bytes = nullptr;
  uint64_t size = 0;
  talos_rt_status status =
      talos_rt_v1_string_view(command, scratch, &bytes, &size);
  if (status != TALOS_RT_OK)
    return status;

  if (size != 0 && bytes[0] == '\0')
    return guarded(context, [&] {
      return runControl(context, std::string_view(bytes + 1, size - 1),
                        *outStatus);
    });

  return guarded(context, [&] {
    // Do not hold the context lock while the child command runs: $system is a
    // blocking host operation, and the shell may itself invoke an Talos
    // executable. std::string supplies the terminating NUL required by libc.
    int shellStatus = std::system(std::string(bytes, size).c_str());
#if defined(_WIN32)
    *outStatus = shellStatus;
#else
    if (shellStatus == -1)
      *outStatus = -1;
    else if (WIFEXITED(shellStatus))
      *outStatus = WEXITSTATUS(shellStatus);
    else if (WIFSIGNALED(shellStatus))
      *outStatus = 128 + WTERMSIG(shellStatus);
    else
      *outStatus = shellStatus;
#endif
    return TALOS_RT_OK;
  });
}
