// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package models

import "time"

// User 用户模型（单用户模式）
type User struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	Username     string    `json:"username" gorm:"uniqueIndex;size:64;not null"`
	PasswordHash string    `json:"-" gorm:"size:255;not null;column:password_hash"` // bcrypt 哈希，不序列化输出
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func (User) TableName() string {
	return "users"
}

// ---- 请求 DTO ----

// LoginRequest 登录请求
type LoginRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required"`
}

// RegisterRequest 注册请求（仅首次初始化时可用）
type RegisterRequest struct {
	Username string `json:"username" validate:"required,min=3,max=32"`
	Password string `json:"password" validate:"required,min=6,max=64"`
}

// ---- 响应 DTO ----

// LoginResponse 登录响应（含 Token）
type LoginResponse struct {
	Token    string `json:"token"`
	Username string `json:"username"`
}

// AuthStatusResponse 认证状态响应（用于判断是否需要注册）
type AuthStatusResponse struct {
	SetupRequired bool   `json:"setup_required"` // true = 需要注册（尚无用户）
	Message       string `json:"message"`
}
