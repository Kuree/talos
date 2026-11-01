//===- Options.td - Talos coverage tool options -----------*- tablegen -*-===//

include "llvm/Option/OptParser.td"

def merge : SubCommand<"merge", "Merge coverage databases",
  "talos-cov merge -o <file> [options] <inputs>...">;
def report : SubCommand<"report", "Report coverage and check thresholds",
  "talos-cov report [options] <inputs>...">;
def inspect : SubCommand<"inspect", "Inspect a coverage database",
  "talos-cov inspect <input>">;

def General_Group : OptionGroup<"General options">;
def Output_Group : OptionGroup<"Output options">;
def Merge_Group : OptionGroup<"Merge options">;
def Report_Group : OptionGroup<"Report options">;

def help : Flag<["--"], "help", [merge, report, inspect]>,
  Group<General_Group>, HelpText<"Display available commands and options">;
def h : Flag<["-"], "h", [merge, report, inspect]>, Alias<help>;

multiclass ValueOption<string name, string metavar, string description,
                       list<SubCommand> commands> {
  def NAME : Separate<["--"], name, commands>, MetaVarName<metavar>,
    HelpText<description>;
  def NAME # _EQ : Joined<["--"], name # "=", commands>,
    Alias<!cast<Option>(NAME)>, MetaVarName<metavar>;
}

let Group = Output_Group in {
  defm output : ValueOption<"output", "<file>",
    "Write output to <file> (required for merge; report defaults to stdout)",
    [merge, report]>;
  def o : Separate<["-"], "o", [merge, report]>, Alias<output>,
    MetaVarName<"<file>">;
  def o_EQ : Joined<["-"], "o=", [merge, report]>, Alias<output>,
    MetaVarName<"<file>">, Flags<[HelpHidden]>;
}

def discard_test_detail : Flag<["--"], "discard-test-detail", [merge]>,
  Group<Merge_Group>, HelpText<"Discard per-test detail from the merged database">;

let Group = Report_Group in {
  let Values = "text,html,json,lcov" in
  defm format : ValueOption<"format", "<text|html|json|lcov>",
    "Select the report format (default: text)", [report]>;
  defm test : ValueOption<"test", "<glob>",
    "Include tests matching <glob> (default: **; * and ? are wildcards)",
    [report]>;
  defm source_root : ValueOption<"source-root", "<dir>",
    "Find source files relative to <dir> for HTML reports", [report]>;
  let Values = "1800-2017,1800-2023" in
  defm std : ValueOption<"std", "<1800-2017|1800-2023>",
    "Select the SystemVerilog version for HTML source highlighting (default: 1800-2023)",
    [report]>;
  defm fail_under : ValueOption<"fail-under", "<metric>=<percent>",
    "Fail below a threshold from 0 to 100; metrics: line, toggle, functional, assertion, fsm (repeatable)",
    [report]>;
}
