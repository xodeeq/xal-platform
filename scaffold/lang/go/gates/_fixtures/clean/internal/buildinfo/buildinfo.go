// Package buildinfo — FIXTURE. A legitimate change that must PASS every gate.
//
// This file is overlaid over the real internal/buildinfo/buildinfo.go by gates/check.test.sh
// together with its test, and scripts/check.sh must exit 0 over the result.
//
// WITHOUT THIS FIXTURE THE SUITE PROVES HALF OF WHAT IT CLAIMS. A gate script that always
// failed would pass every failing fixture above and look perfectly healthy. The clean
// fixture is the control: it changes real code, adds real statements, and must come back
// green — so "the gate can fail" and "the gate can pass" are both observed, not assumed.
package buildinfo

var Version = "dev"

const Name = "<SERVICE>"

func String() string {
	return Name + " " + Version
}

// Stamped reports whether this build carries a linker-stamped version.
func Stamped() bool {
	return Version != "dev"
}
