// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package main

import (
	"io"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	"cosmomail/config"
	"cosmomail/crypto"
	"cosmomail/database"
	"cosmomail/imap"
	"cosmomail/oauth2"
	"cosmomail/routes"
	"cosmomail/sse"

	"github.com/emersion/go-message"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
)

// isProduction 通过 ldflags 注入：生产构建为 "true"，开发构建为 "false"
var isProduction = "false"

// @title           Cosmo Mail API
// @version         1.0
// @description     邮件代收服务 - IMAP 代理收信 + RESTful API
// @host            localhost:8080
// @BasePath        /api/v1

func main() {
	// ⭐ 全局设置 go-message 的字符集解码器
	// 重要：此处返回透传(passthrough)，不让 go-message 自行解码 body！
	// 原因：go-message 内部对 CharsetReader 返回值的处理有 bug，会导致
	//       双重编码(Mojibake)：GBK→UTF-8→Latin-1→UTF-8 = 乱码
	//       我们在 fetcher.go 的 decodeTextContentWithCharset() 中自行正确解码
	message.CharsetReader = func(charset string, input io.Reader) (io.Reader, error) {
		cs := strings.ToLower(strings.Trim(charset, "\"' \t"))
		log.Printf("🔍 [global-CharsetReader] called with charset=%q, normalized=%q → PASSTHROUGH (raw bytes)", charset, cs)
		// ⭐ 一律透传，返回原始字节流，由调用方自行解码
		return input, nil
	}

	// 生产构建自动静默 SQL 日志（database 包读取此环境变量）
	if isProduction == "true" {
		os.Setenv("COSMOMAIL_ENV", "production")
	}
	// 加载配置
	cfg := config.Load()

	// 初始化数据库
	db := database.Init(cfg.Database.DSN)
	defer func() {
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}()

	// 确保安全密钥存在：支持环境变量传入（优先），未设置则自动生成并存入数据库
	database.EnsureSecuritySecrets(db, &cfg.Security.JWTSecret, &cfg.Security.EncryptionKey)

	// 初始化密码加密模块（AES-256-GCM）
	if err := crypto.Init(cfg.Security.EncryptionKey); err != nil {
		log.Fatalf("❌ 加密模块初始化失败: %v", err)
	}

	// 初始化 OAuth2 全局注册中心（注册 Microsoft 等内置 Provider）
	oauth2.InitGlobalRegistry()

	// 创建 Fiber 实例
	// 关键配置：SSE 长连接需要较长的空闲超时和禁用写超时
	app := fiber.New(fiber.Config{
		AppName:            "Cosmo Mail",
		ServerHeader:       "Cosmo Mail",
		IdleTimeout:        60 * time.Second,   // 长连接最大空闲时间（心跳间隔15s，留足余量）
		ReadTimeout:        10 * time.Second,    // 读取请求头超时
		WriteTimeout:       0,                   // 禁用写超时（SSE 长连接需要持续写入）
		ReadBufferSize:     4096,
		WriteBufferSize:    4096,
		DisableKeepalive:   false,               // 保持连接活跃
	})

	// 全局中间件
	app.Use(recover.New())
	// Logger 中间件：排除 SSE 流端点（避免干扰长连接）
	// 注意：SSE 端点 /api/v1/mails/stream 需要保持长连接，logger 的响应拦截可能影响它
	app.Use(logger.New(logger.Config{
		Next: func(c *fiber.Ctx) bool {
			return c.Path() == "/api/v1/mails/stream"
		},
	}))

	// 注册 API 路由
	routes.Register(app, db)

	// 初始化 SSE 实时推送服务
	sse.InitBroker()

	// 启动 IMAP 后台 Worker（所有活跃账号）
	go imap.StartWorkers(db, cfg)

	// 启动 HTTP 服务，并在系统停止时优雅关闭连接和同步 Worker。
	log.Printf("🚀 Cosmo Mail 服务启动于 http://localhost:%d", cfg.Server.Port)
	serverErr := make(chan error, 1)
	go func() {
		serverErr <- app.Listen(cfg.Server.Addr())
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stop)

	select {
	case sig := <-stop:
		log.Printf("🛑 收到停止信号 %s，正在安全退出", sig)
		if err := app.Shutdown(); err != nil {
			log.Printf("⚠️  HTTP 服务关闭异常: %v", err)
		}
		imap.StopWorkers()
	case err := <-serverErr:
		if err != nil {
			log.Fatalf("❌ 服务启动失败: %v", err)
		}
	}
}
