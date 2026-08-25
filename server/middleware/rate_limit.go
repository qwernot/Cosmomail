// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package middleware

import (
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
)

type authRateEntry struct {
	count   int
	resetAt time.Time
}

var authRateState = struct {
	sync.Mutex
	entries map[string]authRateEntry
}{entries: make(map[string]authRateEntry)}

// AuthRateLimit limits password-guessing and setup races on public auth endpoints.
func AuthRateLimit() fiber.Handler {
	return func(c *fiber.Ctx) error {
		now := time.Now()
		key := c.IP()

		authRateState.Lock()
		entry := authRateState.entries[key]
		if entry.resetAt.IsZero() || !now.Before(entry.resetAt) {
			entry = authRateEntry{resetAt: now.Add(time.Minute)}
		}
		if entry.count >= 10 {
			authRateState.Unlock()
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "请求过于频繁，请稍后再试",
			})
		}
		entry.count++
		authRateState.entries[key] = entry
		if len(authRateState.entries) > 1024 {
			for candidate, value := range authRateState.entries {
				if !now.Before(value.resetAt) {
					delete(authRateState.entries, candidate)
				}
			}
		}
		authRateState.Unlock()

		return c.Next()
	}
}
