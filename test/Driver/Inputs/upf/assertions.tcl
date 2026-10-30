proc assert_equal {actual expected} {
    if {$actual ne $expected} {error "expected <$expected>, got <$actual>"}
}
# IEEE 1801-2018 5.11: UPF command failures must be observable by Tcl catch.
proc expect_error {script pattern} {
    set code [catch {uplevel 1 $script} message]
    if {$code != 1 || ![string match $pattern $message]} {
        error "expected TCL_ERROR <$pattern>, got code $code <$message> from <$script>"
    }
}
