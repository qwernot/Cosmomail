// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package middleware

import (
	"strings"

	"cosmomail/services"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

// AuthRequired JWT 认证中间件
func AuthRequired(authService *services.AuthService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		var tokenStr string

		// 优先从 Authorization header 获取
		authHeader := c.Get("Authorization")
		if authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
				tokenStr = parts[1]
			}
		}

		// EventSource 无法设置 Authorization header，因此仅 SSE 端点允许查询参数认证。
		// 其他受保护接口禁止 URL Token，避免凭据进入浏览器历史、代理日志和 Referer。
		if tokenStr == "" && c.Path() == "/api/v1/mails/stream" {
			tokenStr = c.Query("token")
		}

		if tokenStr == "" {
			return c.Status(401).JSON(fiber.Map{"error": "未提供认证令牌"})
		}

		token, err := authService.ParseToken(tokenStr)
		if err != nil || !token.Valid {
			return c.Status(401).JSON(fiber.Map{"error": "认证令牌无效或已过期"})
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			return c.Status(401).JSON(fiber.Map{"error": "无法解析认证信息"})
		}

		c.Locals("user_id", claims["user_id"])
		c.Locals("username", claims["username"])

		return c.Next()
	}
}
