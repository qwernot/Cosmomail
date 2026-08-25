// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Cosmo Mail

package buildinfo

// Values are replaced by release/build scripts through -ldflags -X.
var (
	Version   = "1.1.5"
	BuildTime = "unknown"
	GitCommit = "dev"
)
