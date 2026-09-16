package buildinfo

import "testing"

func TestStringIncludesNameAndVersion(t *testing.T) {
	got := String()
	if want := Name + " " + Version; got != want {
		t.Fatalf("String() = %q, want %q", got, want)
	}
}

func TestVersionDefaultsToDev(t *testing.T) {
	if Version != "dev" {
		t.Fatalf("Version = %q, want %q in an unstamped build", Version, "dev")
	}
}

func TestStampedIsFalseInAnUnstampedBuild(t *testing.T) {
	if Stamped() {
		t.Fatal("Stamped() = true in an unstamped build")
	}
}
