// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package models

import "time"

// MailboxSyncState records the high-water mark for one remote mailbox.
// UIDValidity makes the cursor safe across mailbox recreation on the server.
type MailboxSyncState struct {
	ID          uint   `gorm:"primaryKey"`
	AccountID   uint   `gorm:"not null;uniqueIndex:idx_mailbox_sync_account_folder"`
	Folder      string `gorm:"type:varchar(32);not null;uniqueIndex:idx_mailbox_sync_account_folder"`
	UIDValidity uint32 `gorm:"not null;default:0"`
	LastUID     uint32 `gorm:"not null;default:0"`
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (MailboxSyncState) TableName() string {
	return "mailbox_sync_states"
}
