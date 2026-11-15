// RUN: not talos-opt %s '--lower-talos-to-sim=opt-level=0' -o /dev/null 2>&1 | FileCheck %s
// REQUIRES: compiled-sampler

// Sampling coordinates are not the expression payload of a real array.
// These frozen arrays have identical NaN payloads beside equal finite values.
// IEEE element equality must see the NaNs, rather than compare their zero
// placeholder ranks. Keep the unsupported whole-array relation diagnosed
// until it has elementwise IEEE lowering; complete native array arguments
// are covered independently in the runtime fixture.
// CHECK: error: whole real array constraint values require elementwise IEEE lowering

module attributes {coverage.language_version = 2023 : i32} {
  talos.sv.symbol.definition @s0.top attributes {definition_kind = 0 : i32, hierarchical_name = "top", name = "top", node_id = 0 : i64} {
  }
  talos.sv.symbol.root @s1.$root attributes {hierarchical_name = "\\$root ", name = "$root", node_id = 1 : i64} {
    talos.sv.symbol.compilation_unit @s2 attributes {hierarchical_name = "$unit", node_id = 2 : i64, simulation.vpi_definition_name = "$unit"} {
      talos.sv.type.class_type @s3.Packet attributes {bitstream_width = 257 : i64, declared_interfaces = [], generic_parameter_paths = [], generic_parameter_symbols = [], has_base_constructor_call = false, has_cycles = false, hierarchical_name = "Packet", implemented_interfaces = [], is_abstract = false, is_final = false, is_interface = false, is_uninstantiated = false, name = "Packet", node_id = 3 : i64, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>, this_variable_path = "Packet::this", this_variable_symbol = @s1.$root::@s2::@s3.Packet::@s26.this} {
        talos.sv.symbol.class_property @s4.a attributes {hierarchical_name = "Packet::a", name = "a", node_id = 4 : i64, rand_mode = 1 : i32, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
        }
        talos.sv.symbol.class_property @s5.b attributes {hierarchical_name = "Packet::b", name = "b", node_id = 5 : i64, rand_mode = 1 : i32, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
        }
        talos.sv.symbol.class_property @s6.token attributes {hierarchical_name = "Packet::token", name = "token", node_id = 6 : i64, rand_mode = 1 : i32, semantic_type = !talos.integral<1, false, false, 0 : 0, bit>} {
        }
        talos.sv.symbol.constraint_block @s7.c attributes {hierarchical_name = "Packet::c", name = "c", node_id = 7 : i64, this_variable_path = "Packet::c.this", this_variable_symbol = @s1.$root::@s2::@s3.Packet::@s7.c::@s8.this} {
          talos.sv.constraint.list attributes {item_count = 1 : i64, node_id = 8 : i64} {
            talos.sv.constraint.expression attributes {is_soft = false, node_id = 9 : i64} {
              talos.sv.expression.binary_op attributes {is_signed = false, node_id = 10 : i64, operator_kind = 9 : i32, semantic_type = !talos.integral<1, false, false, 0 : 0, bit>} {
                talos.sv.expression.named_value attributes {is_signed = false, node_id = 11 : i64, referenced_path = "Packet::a", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s4.a, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                }
                talos.sv.expression.named_value attributes {is_signed = false, node_id = 12 : i64, referenced_path = "Packet::b", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s5.b, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                }
              }
            }
          }
          talos.sv.symbol.variable @s8.this attributes {hierarchical_name = "Packet::c.this", is_compiler_generated, is_const, name = "this", node_id = 13 : i64, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
          }
        }
        talos.sv.symbol.subroutine @s9.randomize attributes {hierarchical_name = "Packet::randomize", is_builtin, is_declared_virtual, is_randomize, is_virtual, name = "randomize", node_id = 14 : i64, semantic_type = !talos.subroutine<() -> !talos.integral<32, true, false, 31 : 0, int>, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 15 : i64} {
          }
        }
        talos.sv.symbol.subroutine @s10.pre_randomize attributes {hierarchical_name = "Packet::pre_randomize", is_builtin, name = "pre_randomize", node_id = 16 : i64, semantic_type = !talos.subroutine<() -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 17 : i64} {
          }
        }
        talos.sv.symbol.subroutine @s11.post_randomize attributes {hierarchical_name = "Packet::post_randomize", is_builtin, name = "post_randomize", node_id = 18 : i64, semantic_type = !talos.subroutine<() -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 19 : i64} {
          }
        }
        talos.sv.symbol.subroutine @s12.get_randstate attributes {hierarchical_name = "Packet::get_randstate", is_builtin, name = "get_randstate", node_id = 20 : i64, semantic_type = !talos.subroutine<() -> !talos.string, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 21 : i64} {
          }
        }
        talos.sv.symbol.subroutine @s13.set_randstate attributes {hierarchical_name = "Packet::set_randstate", is_builtin, name = "set_randstate", node_id = 22 : i64, semantic_type = !talos.subroutine<(!talos.string) -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 23 : i64} {
          }
          talos.sv.symbol.formal_argument @s14.state attributes {direction = 0 : i32, hierarchical_name = "Packet::set_randstate.state", name = "state", node_id = 24 : i64, semantic_type = !talos.string} {
          }
        }
        talos.sv.symbol.subroutine @s15.srandom attributes {hierarchical_name = "Packet::srandom", is_builtin, name = "srandom", node_id = 25 : i64, semantic_type = !talos.subroutine<(!talos.integral<32, true, false, 31 : 0, int>) -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 26 : i64} {
          }
          talos.sv.symbol.formal_argument @s16.seed attributes {direction = 0 : i32, hierarchical_name = "Packet::srandom.seed", name = "seed", node_id = 27 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
          }
        }
        talos.sv.symbol.subroutine @s17.rand_mode attributes {hierarchical_name = "Packet::rand_mode", is_builtin, name = "rand_mode", node_id = 28 : i64, semantic_type = !talos.subroutine<(!talos.integral<1, false, false, 0 : 0, bit>) -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 29 : i64} {
          }
          talos.sv.symbol.formal_argument @s18.on_ff attributes {direction = 0 : i32, hierarchical_name = "Packet::rand_mode.on_ff", name = "on_ff", node_id = 30 : i64, semantic_type = !talos.integral<1, false, false, 0 : 0, bit>} {
          }
        }
        talos.sv.symbol.subroutine @s19.constraint_mode attributes {hierarchical_name = "Packet::constraint_mode", is_builtin, name = "constraint_mode", node_id = 31 : i64, semantic_type = !talos.subroutine<(!talos.integral<1, false, false, 0 : 0, bit>) -> !talos.void, false>, subroutine_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.list attributes {node_id = 32 : i64} {
          }
          talos.sv.symbol.formal_argument @s20.on_ff attributes {direction = 0 : i32, hierarchical_name = "Packet::constraint_mode.on_ff", name = "on_ff", node_id = 33 : i64, semantic_type = !talos.integral<1, false, false, 0 : 0, bit>} {
          }
        }
        talos.sv.symbol.variable @s26.this attributes {hierarchical_name = "Packet::this", is_compiler_generated, is_const, name = "this", node_id = 96 : i64, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
        }
      }
    }
    talos.sv.symbol.instance @s21.top attributes {hierarchical_name = "top", is_uninstantiated = false, name = "top", node_id = 34 : i64, referenced_path = "top", referenced_symbol = @s0.top} {
      talos.sv.symbol.instance_body @s22.top attributes {hierarchical_name = "top", name = "top", node_id = 35 : i64, simulation.vpi_automatic = false, simulation.vpi_cell_instance = false, simulation.vpi_definition_name = "top", simulation.vpi_top = true, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64, vpi_scope_kind = 32 : i32} {
        talos.sv.symbol.variable @s23.packet attributes {hierarchical_name = "top.packet", lifetime = 1 : i32, name = "packet", node_id = 36 : i64, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
          talos.sv.expression.new_class attributes {is_signed = false, is_super_class = false, node_id = 37 : i64, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
          }
        }
        talos.sv.symbol.variable @s24.status attributes {hierarchical_name = "top.status", lifetime = 1 : i32, name = "status", node_id = 38 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
        }
        talos.sv.symbol.procedural_block @s25 attributes {hierarchical_name = "top", node_id = 39 : i64, procedure_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.block attributes {node_id = 40 : i64} {
            talos.sv.statement.list attributes {node_id = 41 : i64} {
              talos.sv.statement.expression_statement attributes {node_id = 42 : i64} {
                talos.sv.expression.assignment attributes {assignment_kind = 0 : i32, is_signed = false, node_id = 43 : i64, semantic_type = !talos.real} {
                  talos.sv.expression.element_select attributes {is_signed = false, node_id = 44 : i64, semantic_type = !talos.real} {
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "a", node_id = 45 : i64, referenced_path = "Packet::a", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s4.a, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 46 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                    talos.sv.expression.integer_literal attributes {constant_value = "0", is_declared_unsized = true, is_signed = true, node_id = 47 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                    }
                  }
                  talos.sv.expression.call attributes {argument_count = 1 : i64, callee_name = "$bitstoreal", constraint_restrictions = [], defaulted_arguments = array<i64: 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_signed = false, is_super_class = false, is_system_call = true, node_id = 48 : i64, semantic_type = !talos.real, subroutine_kind = 0 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                    talos.sv.expression.integer_literal attributes {constant_value = "64'h7ff8000000000011", is_signed = false, node_id = 49 : i64, semantic_type = !talos.ranged_packed_array<63 : 0 x !talos.integral<1, false, false, 0 : 0, bit>>} {
                    }
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 50 : i64} {
                talos.sv.expression.assignment attributes {assignment_kind = 0 : i32, is_signed = false, node_id = 51 : i64, semantic_type = !talos.real} {
                  talos.sv.expression.element_select attributes {is_signed = false, node_id = 52 : i64, semantic_type = !talos.real} {
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "b", node_id = 53 : i64, referenced_path = "Packet::b", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s5.b, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 54 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                    talos.sv.expression.integer_literal attributes {constant_value = "0", is_declared_unsized = true, is_signed = true, node_id = 55 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                    }
                  }
                  talos.sv.expression.call attributes {argument_count = 1 : i64, callee_name = "$bitstoreal", constraint_restrictions = [], defaulted_arguments = array<i64: 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_signed = false, is_super_class = false, is_system_call = true, node_id = 56 : i64, semantic_type = !talos.real, subroutine_kind = 0 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                    talos.sv.expression.integer_literal attributes {constant_value = "64'h7ff8000000000011", is_signed = false, node_id = 57 : i64, semantic_type = !talos.ranged_packed_array<63 : 0 x !talos.integral<1, false, false, 0 : 0, bit>>} {
                    }
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 58 : i64} {
                talos.sv.expression.assignment attributes {assignment_kind = 0 : i32, is_signed = false, node_id = 59 : i64, semantic_type = !talos.real} {
                  talos.sv.expression.element_select attributes {is_signed = false, node_id = 60 : i64, semantic_type = !talos.real} {
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "a", node_id = 61 : i64, referenced_path = "Packet::a", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s4.a, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 62 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                    talos.sv.expression.integer_literal attributes {constant_value = "1", is_declared_unsized = true, is_signed = true, node_id = 63 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                    }
                  }
                  talos.sv.expression.real_literal attributes {constant_value = "1", is_signed = false, node_id = 64 : i64, semantic_type = !talos.real} {
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 65 : i64} {
                talos.sv.expression.assignment attributes {assignment_kind = 0 : i32, is_signed = false, node_id = 66 : i64, semantic_type = !talos.real} {
                  talos.sv.expression.element_select attributes {is_signed = false, node_id = 67 : i64, semantic_type = !talos.real} {
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "b", node_id = 68 : i64, referenced_path = "Packet::b", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s5.b, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 69 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                    talos.sv.expression.integer_literal attributes {constant_value = "1", is_declared_unsized = true, is_signed = true, node_id = 70 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                    }
                  }
                  talos.sv.expression.real_literal attributes {constant_value = "1", is_signed = false, node_id = 71 : i64, semantic_type = !talos.real} {
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 72 : i64} {
                talos.sv.expression.call attributes {argument_count = 2 : i64, callee_name = "rand_mode", constraint_restrictions = [], defaulted_arguments = array<i64: 0, 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_builtin_method, is_signed = false, is_super_class = false, is_system_call = true, node_id = 73 : i64, semantic_type = !talos.void, subroutine_kind = 0 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                  talos.sv.expression.member_access attributes {is_signed = false, member_name = "a", node_id = 74 : i64, referenced_path = "Packet::a", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s4.a, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                    talos.sv.expression.named_value attributes {is_signed = false, node_id = 75 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                    }
                  }
                  talos.sv.expression.integer_literal attributes {constant_value = "0", is_declared_unsized = true, is_signed = true, node_id = 76 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 77 : i64} {
                talos.sv.expression.call attributes {argument_count = 2 : i64, callee_name = "rand_mode", constraint_restrictions = [], defaulted_arguments = array<i64: 0, 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_builtin_method, is_signed = false, is_super_class = false, is_system_call = true, node_id = 78 : i64, semantic_type = !talos.void, subroutine_kind = 0 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                  talos.sv.expression.member_access attributes {is_signed = false, member_name = "b", node_id = 79 : i64, referenced_path = "Packet::b", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s5.b, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                    talos.sv.expression.named_value attributes {is_signed = false, node_id = 80 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                    }
                  }
                  talos.sv.expression.integer_literal attributes {constant_value = "0", is_declared_unsized = true, is_signed = true, node_id = 81 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 82 : i64} {
                talos.sv.expression.assignment attributes {assignment_kind = 0 : i32, is_signed = true, node_id = 83 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                  talos.sv.expression.named_value attributes {is_signed = true, node_id = 84 : i64, referenced_path = "top.status", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s24.status, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                  }
                  talos.sv.expression.call attributes {argument_count = 1 : i64, callee_name = "randomize", constraint_restrictions = [], defaulted_arguments = array<i64: 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_builtin_method, is_signed = true, is_super_class = false, is_system_call = true, node_id = 85 : i64, semantic_type = !talos.integral<32, true, false, 31 : 0, int>, subroutine_kind = 0 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                    talos.sv.expression.named_value attributes {is_signed = false, node_id = 86 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                    }
                  }
                }
              }
              talos.sv.statement.expression_statement attributes {node_id = 87 : i64} {
                talos.sv.expression.call attributes {argument_count = 3 : i64, callee_name = "$display", constraint_restrictions = [], defaulted_arguments = array<i64: 0, 0, 0>, has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_signed = false, is_super_class = false, is_system_call = true, node_id = 88 : i64, semantic_type = !talos.void, subroutine_kind = 1 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s21.top::@s22.top} {
                  talos.sv.expression.string_literal attributes {constant_value = "array equality status=%0d procedural=%0d", is_signed = false, node_id = 89 : i64, semantic_type = !talos.ranged_packed_array<319 : 0 x !talos.integral<1, false, false, 0 : 0, bit>>} {
                  }
                  talos.sv.expression.named_value attributes {is_signed = true, node_id = 90 : i64, referenced_path = "top.status", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s24.status, semantic_type = !talos.integral<32, true, false, 31 : 0, int>} {
                  }
                  talos.sv.expression.binary_op attributes {is_signed = false, node_id = 91 : i64, operator_kind = 9 : i32, semantic_type = !talos.integral<1, false, false, 0 : 0, bit>} {
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "a", node_id = 92 : i64, referenced_path = "Packet::a", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s4.a, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 93 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                    talos.sv.expression.member_access attributes {is_signed = false, member_name = "b", node_id = 94 : i64, referenced_path = "Packet::b", referenced_symbol = @s1.$root::@s2::@s3.Packet::@s5.b, semantic_type = !talos.ranged_unpacked_array<0 : 1 x !talos.real>} {
                      talos.sv.expression.named_value attributes {is_signed = false, node_id = 95 : i64, referenced_path = "top.packet", referenced_symbol = @s1.$root::@s21.top::@s22.top::@s23.packet, semantic_type = !talos.class_handle<@s1.$root::@s2::@s3.Packet>} {
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
