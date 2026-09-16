// Package buildinfo — FIXTURE. Deliberately not gofmt-clean.
//
// This file is overlaid over the real internal/buildinfo/buildinfo.go by gates/check.test.sh
// and must make scripts/check.sh fail AT THE FORMAT GATE, naming it. It differs from the
// real file only in whitespace: leading spaces where gofmt requires a tab, and padding
// around the operators. Nothing here is a syntax error — the point is that the code COMPILES
// and still fails, which is what proves the format gate is doing its own work rather than
// riding on a compile error.
package buildinfo

var Version = "dev"

const Name = "<SERVICE>"

func String() string {
        return Name  +  " "  +  Version
}
