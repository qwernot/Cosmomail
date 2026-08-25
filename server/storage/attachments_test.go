package storage

import (
	"path/filepath"
	"testing"
)

func TestAttachmentPathStaysInsideCache(t *testing.T) {
	path := AttachmentPath(42, "1.2", `../../outside.exe`)
	if !IsAttachmentPath(path) {
		t.Fatalf("generated path escaped attachment directory: %s", path)
	}
	if filepath.Base(path) == "outside.exe" {
		t.Fatalf("untrusted filename was used directly: %s", path)
	}
}

func TestIsAttachmentPathRejectsTraversal(t *testing.T) {
	outside := filepath.Join(AttachmentDir, "..", "outside.txt")
	if IsAttachmentPath(outside) {
		t.Fatalf("accepted path outside attachment directory: %s", outside)
	}
}
