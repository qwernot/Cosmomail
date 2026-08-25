// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package storage

import (
	"crypto/sha256"
	"fmt"
	"path/filepath"
	"strings"
	"unicode"
)

// AttachmentDir is the only directory in which downloaded attachment files may live.
var AttachmentDir = filepath.Join(".", "data", "attachments")

// AttachmentPath builds a deterministic path without using the untrusted mail filename
// as a path component. The original extension is kept only when it is short and safe.
func AttachmentPath(mailID uint, discriminator, filename string) string {
	digest := sha256.Sum256([]byte(discriminator + "\x00" + filename))
	ext := safeExtension(filename)
	name := fmt.Sprintf("%d_%x%s", mailID, digest[:12], ext)
	return filepath.Join(AttachmentDir, name)
}

// IsAttachmentPath rejects legacy or corrupted database paths outside AttachmentDir.
func IsAttachmentPath(path string) bool {
	if path == "" {
		return false
	}
	base, err := filepath.Abs(AttachmentDir)
	if err != nil {
		return false
	}
	target, err := filepath.Abs(path)
	if err != nil {
		return false
	}
	rel, err := filepath.Rel(base, target)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func safeExtension(filename string) string {
	ext := strings.ToLower(filepath.Ext(filepath.Base(filename)))
	if len(ext) > 16 {
		return ""
	}
	for _, r := range ext {
		if r != '.' && !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			return ""
		}
	}
	return ext
}
