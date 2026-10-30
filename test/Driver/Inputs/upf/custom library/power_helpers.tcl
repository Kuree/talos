# IEEE 1801-2018 5.1: user Tcl procedure libraries may issue UPF commands.
namespace eval ::power_helpers {
    proc declare_switchable {name instance control} {
        create_power_domain $name -elements [list $instance]
        foreach net {VDD VSS VDD_SW} {create_supply_net $net}
        set_domain_supply_net $name -primary_power_net VDD_SW -primary_ground_net VSS
        create_power_switch SW -domain $name \
            -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW} \
            -control_port [list en $control] -on_state {ON vin en}
    }
    proc broken {} {
        create_power_domain Broken -elements nonexistent_instance
    }
}
package provide PowerHelpers 1.2
