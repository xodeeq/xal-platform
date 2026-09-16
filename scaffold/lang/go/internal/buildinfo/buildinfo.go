// Package buildinfo reports what this binary is.
//
// It exists at seeding so the gate has something real to compile, vet, lint, test and
// measure. A gate chain that has never run over a single package is a gate chain nobody has
// seen work, and the point of seeding is that the repo arrives with its gate PROVEN rather
// than merely present.
package buildinfo

// Version is the build's version string. It is overridden at link time in a release build
// (-ldflags "-X ...") and reads "dev" in every other build, so an unstamped binary says so
// rather than claiming a version it does not have.
var Version = "dev"

// Name is the service's name, used in logs and in the version line.
const Name = "<SERVICE>"

// String renders the one line a `--version` flag or a startup log prints.
func String() string {
	return Name + " " + Version
}
