// Command <SERVICE> is the service binary.
//
// ONE IMAGE, TWO SUBCOMMANDS. `serve` runs the HTTP service; `migrate` applies database
// migrations as a release step. They are the same binary on purpose: the migration that runs
// and the code that runs are then the same build, and "which version of the schema does this
// version of the service expect" stops being a question anyone has to answer from memory.
//
// SEEDED AS A STUB. Both subcommands exit non-zero with a clear message. The stub exists so
// the image builds and the gate chain has a main package to compile — not as a placeholder
// to be fleshed out arbitrarily. The first implementation session replaces each body with
// the real thing, against the contract in openapi.yaml and the admitted spec.
package main

import (
	"fmt"
	"os"

	"github.com/xodeeq/<SERVICE>/internal/buildinfo"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "serve":
		fail("serve is not implemented yet")
	case "migrate":
		fail("migrate is not implemented yet")
	case "version":
		fmt.Println(buildinfo.String())
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s <serve|migrate|version>\n", buildinfo.Name)
}

// fail exits non-zero rather than returning a zero exit with a warning. A process that
// cannot do the thing it was asked to do must not look like one that did.
func fail(msg string) {
	fmt.Fprintf(os.Stderr, "%s: %s\n", buildinfo.Name, msg)
	os.Exit(1)
}
