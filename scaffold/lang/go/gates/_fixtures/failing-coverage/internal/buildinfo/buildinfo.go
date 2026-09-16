// Package buildinfo — FIXTURE. Deliberately below its coverage floor.
//
// This file is overlaid over the real internal/buildinfo/buildinfo.go by gates/check.test.sh
// and must make scripts/check.sh fail AT THE COVERAGE GATE, naming it.
//
// The added function is EXPORTED on purpose. An unexported function that nothing calls is
// dead code, which the `unused` linter catches first — and the fixture would then prove the
// LINT gate works while claiming to prove the coverage gate does. Exported, it is legitimate
// code that simply has no test, which is exactly the condition a coverage floor exists to
// catch, and it reaches gate 6 untouched.
package buildinfo

var Version = "dev"

const Name = "<SERVICE>"

func String() string {
	return Name + " " + Version
}

// Describe is exported, reachable, and covered by no test. Its statements drag the package's
// line coverage below the floor in coverage-floors.
func Describe(verbose bool) string {
	if verbose {
		return "service " + Name + " at version " + Version
	}
	if Version == "dev" {
		return Name + " (unstamped)"
	}
	return String()
}
