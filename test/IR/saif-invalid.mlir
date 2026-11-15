// RUN: talos-opt --split-input-file --verify-diagnostics %s

module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        // expected-error@+1 {{expected a bounded nonnegative decimal spelling}}
        saif.metric TC #saif.number<"-1">
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        // expected-error@+1 {{number must be finite in binary64}}
        saif.metric TC #saif.number<"1e9999">
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      // expected-error@+1 {{bit index must have canonical unsigned decimal spelling}}
      saif.signal #saif.path<[#saif.identifier<name = "a", index = "01">]> {

      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      // expected-error@+1 {{identifier must contain 1..16384 non-whitespace characters}}
      saif.signal #saif.path<[#saif.identifier<name = "">]> {

      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      // expected-error@+1 {{backward signal name must be a simple identifier}}
      saif.signal #saif.path<[]> {

      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        saif.conditions {
          // expected-error@+1 {{condition requires 1..4096 postfix tokens}}
          saif.when attributes {condition = #saif.condition<[]>} { saif.metric TC #saif.number<"1"> }
        }
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        saif.conditions {
          // expected-error@+1 {{condition postfix stack underflow}}
          saif.when attributes {condition = #saif.condition<[#saif.condition_token<opcode = and>]>} { saif.metric TC #saif.number<"1"> }
        }
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        saif.conditions {
          // expected-error@+1 {{condition must produce exactly one value}}
          saif.when attributes {condition = #saif.condition<[#saif.condition_token<opcode = pin, pin = <name = "a">>, #saif.condition_token<opcode = pin, pin = <name = "b">>]>} { saif.metric TC #saif.number<"1"> }
        }
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        saif.conditions {
          // expected-error@+1 {{pin token requires an identifier}}
          saif.when attributes {condition = #saif.condition<[#saif.condition_token<opcode = pin>]>} { saif.metric TC #saif.number<"1"> }
        }
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    saif.header timescale
    saif.header duration {value = #saif.number<"1">}
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
    saif.ports {
      saif.signal #saif.path<[#saif.identifier<name = "q">]> {
        saif.conditions {
          // expected-error@+1 {{operator cannot carry a pin}}
          saif.when attributes {condition = #saif.condition<[#saif.condition_token<opcode = pin, pin = <name = "a">>, #saif.condition_token<opcode = not, pin = <name = "a">>]>} { saif.metric TC #saif.number<"1"> }
        }
      }
    }
  }
  }
}

// -----
module {
  saif.file "raw" {
    saif.header version {text = "2.0"}
    saif.header direction {text = "backward"}
    saif.header design
    saif.header date
    saif.header vendor
    saif.header program_name
    saif.header program_version
    saif.header divider
    // expected-error@+1 {{TIMESCALE amount must be the integer 1, 10, or 100}}
    saif.header timescale {scale = #saif.timescale<amount = <"1e0">, unit = "ns">}
    saif.header duration {value = #saif.number<"1">}

  }
}

// -----
module {
  saif.file "raw" {
    // expected-error@+1 {{SAIF strings must be single-line}}
    saif.header design {text = "two\0Alines"}
  }
}

// -----
module {
  // expected-error@+1 {{'saif.header' op has an illegal parent}}
  saif.header version {text = "2.0"}
}

// -----
module {
  saif.file "raw" {
    // expected-error@+1 {{DURATION requires only a number value}}
    saif.header duration
  }
}

// -----
module {
  saif.file "raw" {
    // expected-error@+1 {{is not permitted in saif.file}}
    saif.metric TC #saif.number<"1">
  }
}

// -----
module {
  saif.file "raw" {
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
      saif.ports {
        saif.signal #saif.path<[#saif.identifier<name = "Q">]> {
          // expected-error@+1 {{requires at least one COND item}}
          saif.conditions {}
        }
      }
    }
  }
}

// -----
module {
  saif.file "raw" {
    saif.instance #saif.path<[#saif.identifier<name = "top">]> {
      saif.ports {
        saif.signal #saif.path<[#saif.identifier<name = "Q">]> {
          // expected-error@+1 {{requires at least one IOPATH item}}
          saif.paths {}
        }
      }
    }
  }
}

// -----
module {
  // expected-error@+1 {{region should have no arguments}}
  saif.file "raw" {
  ^bb0(%arg: i1):
  }
}
