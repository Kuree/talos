proc declare_domain {name instance} {
    set matches [find_objects . -pattern $instance -object_type inst]
    if {[llength $matches] != 1} {error "expected exactly one domain instance"}
    set label "電源"
    if {[string length $label] != 2} {error "UTF-8 string handling failed"}
    if {[clock format 0 -format %Y -gmt 1] ne "1970"} {error "core clock initialization failed"}
    create_power_domain $name -elements $matches
}
