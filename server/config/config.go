// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package config

import (
	"os"
	"strconv"
	"time"
)

// Config 应用全局配置
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	IMAP     IMAPConfig
	Security SecurityConfig
	OAuth2   OAuth2Config
}

// ServerConfig HTTP 服务配置
type ServerConfig struct {
	Port int    // 监听端口，默认 8080
	Host string // 监听地址，默认 0.0.0.0
}

func (s ServerConfig) Addr() string {
	return s.Host + ":" + strconv.Itoa(s.Port)
}

// DatabaseConfig 数据库配置
type DatabaseConfig struct {
	DSN string // SQLite 连接路径，默认 data/cosmomail.db
}

// IMAPConfig IMAP 同步配置
type IMAPConfig struct {
	PollInterval      int   // 定时轮询间隔（秒），默认 5
	IDLEEnabled       bool  // 是否启用 IDLE，默认 true
	MaxConcurrent     int   // 最大并发连接数，默认 10
	SyncBatchSize     int   // 每次拉取邮件数量上限，默认 50
	MaxAttachmentSize int64 // 单附件大小上限（MB），默认 50，0=不限制
	MinDiskFreeMB     int64 // 最小剩余磁盘空间（MB），默认 1024（1GB）
	CacheThresholdMB  int64 // 附件缓存阈值（MB），默认 2，小于此值立即缓存
	CacheExpireDays   int   // 缓存过期天数，默认 30 天
	AutoCacheEnabled  bool  // 是否启用自动缓存（懒加载首次下载后缓存到本地），默认 false
}

// GetMaxAttachmentSize 获取单附件大小上限（字节）
func (c *IMAPConfig) GetMaxAttachmentSize() int64 {
	if c.MaxAttachmentSize <= 0 {
		return 50 * 1024 * 1024 // 默认 50MB
	}
	return c.MaxAttachmentSize * 1024 * 1024
}

// GetMinDiskFree 获取最小剩余磁盘空间（字节）
func (c *IMAPConfig) GetMinDiskFree() int64 {
	if c.MinDiskFreeMB <= 0 {
		return 1024 * 1024 * 1024 // 默认 1GB
	}
	return c.MinDiskFreeMB * 1024 * 1024
}

// GetCacheThreshold 获取附件缓存阈值（字节）
func (c *IMAPConfig) GetCacheThreshold() int64 {
	if c.CacheThresholdMB <= 0 {
		return 2 * 1024 * 1024 // 默认 2MB
	}
	return c.CacheThresholdMB * 1024 * 1024
}

// GetCacheExpireDuration 获取缓存过期时间
func (c *IMAPConfig) GetCacheExpireDuration() time.Duration {
	if c.CacheExpireDays <= 0 {
		return 30 * 24 * time.Hour // 默认30天
	}
	return time.Duration(c.CacheExpireDays) * 24 * time.Hour
}

// IsAutoCacheEnabled 是否启用自动缓存
func (c *IMAPConfig) IsAutoCacheEnabled() bool {
	return c.AutoCacheEnabled
}

// SecurityConfig 安全配置
type SecurityConfig struct {
	EncryptionKey string // 密码加密密钥（从环境变量读取）
	JWTSecret     string // JWT 密钥（预留）
}

// OAuth2Config OAuth2 全局配置（混合模式 Client ID 管理）
type OAuth2Config struct {
	// Microsoft OAuth2 配置
	MicrosoftClientID string // Microsoft 默认 Client ID（可被环境变量或用户自定义覆盖）
}

// Load 加载配置，优先从环境变量读取，使用默认值兜底
func Load() *Config {
	port := 8080
	if v := os.Getenv("COSMOMAIL_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil && p > 0 {
			port = p
		}
	}

	pollInterval := 5
	if v := os.Getenv("COSMOMAIL_POLL_INTERVAL"); v != "" {
		if p, err := strconv.Atoi(v); err == nil && p >= 5 {
			pollInterval = p
		}
	}

	maxConcurrent := 10
	if v := os.Getenv("COSMOMAIL_MAX_CONCURRENT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil && p > 0 {
			maxConcurrent = p
		}
	}

	syncBatchSize := 50
	if v := os.Getenv("COSMOMAIL_SYNC_BATCH_SIZE"); v != "" {
		if p, err := strconv.Atoi(v); err == nil && p > 0 {
			syncBatchSize = p
		}
	}

	maxAttachmentSize := int64(50) // 默认 50MB
	if v := os.Getenv("COSMOMAIL_MAX_ATTACHMENT_SIZE"); v != "" {
		if p, err := strconv.ParseInt(v, 10, 64); err == nil && p >= 0 {
			maxAttachmentSize = p
		}
	}

	minDiskFreeMB := int64(1024) // 默认 1GB
	if v := os.Getenv("COSMOMAIL_MIN_DISK_FREE"); v != "" {
		if p, err := strconv.ParseInt(v, 10, 64); err == nil && p >= 0 {
			minDiskFreeMB = p
		}
	}

	cacheThresholdMB := int64(2) // 默认 2MB
	if v := os.Getenv("COSMOMAIL_CACHE_THRESHOLD"); v != "" {
		if p, err := strconv.ParseInt(v, 10, 64); err == nil && p >= 0 {
			cacheThresholdMB = p
		}
	}

	cacheExpireDays := 30
	if v := os.Getenv("COSMOMAIL_CACHE_EXPIRE_DAYS"); v != "" {
		if p, err := strconv.Atoi(v); err == nil && p > 0 {
			cacheExpireDays = p
		}
	}

	autoCacheEnabled := false
	if v := os.Getenv("COSMOMAIL_AUTO_CACHE"); v != "" {
		autoCacheEnabled = v == "1" || v == "true" || v == "TRUE" || v == "True"
	}

	dsn := "data/cosmomail.db"
	if v := os.Getenv("COSMOMAIL_DSN"); v != "" {
		dsn = v
	}

	return &Config{
		Server: ServerConfig{
			Port: port,
			Host: getEnv("COSMOMAIL_HOST", "0.0.0.0"),
		},
		Database: DatabaseConfig{
			DSN: dsn,
		},
		IMAP: IMAPConfig{
			PollInterval:      pollInterval,
			IDLEEnabled:       getEnvBool("COSMOMAIL_IDLE_ENABLED", true),
			MaxConcurrent:     maxConcurrent,
			SyncBatchSize:     syncBatchSize,
			MaxAttachmentSize: maxAttachmentSize,
			MinDiskFreeMB:     minDiskFreeMB,
			CacheThresholdMB:  cacheThresholdMB,
			CacheExpireDays:   cacheExpireDays,
			AutoCacheEnabled:  autoCacheEnabled,
		},
		Security: SecurityConfig{
			// 安全密钥由 EnsureSecuritySecrets 统一管理：
			//   - 默认自动生成随机密钥并持久化到数据库
			//   - 可通过环境变量 COSMOMAIL_JWT_SECRET / COSMOMAIL_ENCRYPT_KEY 显式指定（优先级更高）
			EncryptionKey: "",
			JWTSecret:     "",
		},
		OAuth2: OAuth2Config{
			MicrosoftClientID: getEnv("COSMOMAIL_OAUTH_MICROSOFT_CLIENT_ID", ""),
		},
	}
}

// getEnv 读取环境变量，不存在则返回默认值
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// getEnvBool 读取布尔环境变量
func getEnvBool(key string, fallback bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v == "1" || v == "true" || v == "TRUE" || v == "True"
}
