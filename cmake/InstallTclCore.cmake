# Only core initialization / autoload scripts accompany the compiler. UTF-8,
# UTF-16 and Latin-1 are built into Tcl; legacy *.enc tables are not installed.
file(MAKE_DIRECTORY "${DEST}/lib/tcl9.0")
file(COPY "${BINARY}/libtcl9.0.a" DESTINATION "${DEST}/lib")
file(GLOB scripts "${SOURCE}/library/*.tcl")
list(FILTER scripts EXCLUDE REGEX "/install\\.tcl$")
file(COPY ${scripts} "${SOURCE}/library/tclIndex" DESTINATION "${DEST}/lib/tcl9.0")
file(MAKE_DIRECTORY "${DEST}/lib/tcl9.0/opt0.4")
file(COPY "${SOURCE}/library/opt/" DESTINATION "${DEST}/lib/tcl9.0/opt0.4")
# clock.tcl uses the core message catalog package even for UTC formatting.
file(MAKE_DIRECTORY "${DEST}/lib/tcl9.0/msgcat1.7.1")
file(COPY "${SOURCE}/library/msgcat/msgcat.tcl" DESTINATION "${DEST}/lib/tcl9.0/msgcat1.7.1")
file(WRITE "${DEST}/lib/tcl9.0/msgcat1.7.1/pkgIndex.tcl"
  "package ifneeded msgcat 1.7.1 [list source [file join $dir msgcat.tcl]]\n")
# Remove artifacts left by older configurations of this generated prefix.
file(REMOVE_RECURSE "${DEST}/lib/tcl9.0/encoding")
file(REMOVE_RECURSE "${DEST}/lib/tcl9.0/cookiejar0.2")
file(REMOVE "${DEST}/lib/tcl9.0/install.tcl" "${DEST}/lib/tcl9.0/tclAppInit.c")
