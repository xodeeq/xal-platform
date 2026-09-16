package buildinfo

import "testing"

func TestStringIncludesNameAndVersion(t *testing.T) {
	got := String()
	if want := Name + " " + Version; got != want {
		t.Fatalf("String() = %q, want %q", got, want)
	}
}

func TestVersionDefaultsToDev(t *testing.T) {
	// An unstamped build must SAY it is unstamped. The failure this guards against is a
	// binary in production reporting a version nobody built.
	if Version != "dev" {
		t.Fatalf("Version = %q, want %q in an unstamped build", Version, "dev")
	}
}
