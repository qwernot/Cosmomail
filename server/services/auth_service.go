// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package services

import (
	"errors"
	"fmt"
	"log"
	"time"

	"cosmomail/config"
	"cosmomail/models"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// AuthService 认证服务
type AuthService struct {
	db        *gorm.DB
	jwtSecret []byte
}

// NewAuthService 创建认证服务实例
func NewAuthService(db *gorm.DB, cfg *config.Config) *AuthService {
	return &AuthService{
		db:        db,
		jwtSecret: []byte(cfg.Security.JWTSecret),
	}
}

var (
	ErrInvalidCredentials = errors.New("用户名或密码错误")
	ErrUserExists         = errors.New("管理员已存在，不可重复注册")
)

// HashPassword 对密码进行 bcrypt 哈希
func (s *AuthService) HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// VerifyPassword 验证密码是否匹配哈希值
func (s *AuthService) VerifyPassword(password, hash string) error {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
}

// GenerateToken 生成 JWT Token（7天有效期）
func (s *AuthService) GenerateToken(user *models.User) (string, error) {
	claims := jwt.MapClaims{
		"user_id":  user.ID,
		"username": user.Username,
		"exp":      time.Now().Add(7 * 24 * time.Hour).Unix(),
		"iat":      time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.jwtSecret)
}

// ParseToken 解析并验证 JWT Token
func (s *AuthService) ParseToken(tokenStr string) (*jwt.Token, error) {
	return jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("无效的签名方法")
		}
		return s.jwtSecret, nil
	})
}

// Login 用户登录
func (s *AuthService) Login(req models.LoginRequest) (*models.LoginResponse, error) {
	var user models.User
	result := s.db.Where("username = ?", req.Username).First(&user)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, result.Error
	}

	if err := s.VerifyPassword(req.Password, user.PasswordHash); err != nil {
		return nil, ErrInvalidCredentials
	}

	token, err := s.GenerateToken(&user)
	if err != nil {
		return nil, err
	}

	return &models.LoginResponse{Token: token, Username: user.Username}, nil
}

// Register 首次注册管理员（单用户模式：仅允许注册一个）
func (s *AuthService) Register(req models.RegisterRequest) error {
	var count int64
	s.db.Model(&models.User{}).Count(&count)
	if count > 0 {
		return ErrUserExists
	}

	hashedPassword, err := s.HashPassword(req.Password)
	if err != nil {
		return err
	}

	user := &models.User{
		Username:     req.Username,
		PasswordHash: hashedPassword,
	}
	return s.db.Create(user).Error
}

// GetAuthStatus 查询是否已设置管理员（前端据此决定显示登录还是注册页）
func (s *AuthService) GetAuthStatus() *models.AuthStatusResponse {
	var count int64
	s.db.Model(&models.User{}).Count(&count)

	if count == 0 {
		return &models.AuthStatusResponse{
			SetupRequired: true,
			Message:       "欢迎使用 Cosmo Mail，请先创建管理员账号",
		}
	}
	return &models.AuthStatusResponse{
		SetupRequired: false,
		Message:       "已就绪",
	}
}

// SeedDefaultUser 开发环境：自动创建默认管理员（仅在无用户时生效）
func (s *AuthService) SeedDefaultUser(username, password string) error {
	var count int64
	s.db.Model(&models.User{}).Count(&count)
	if count > 0 {
		return nil // 已有用户则跳过
	}

	hashedPassword, err := s.HashPassword(password)
	if err != nil {
		return err
	}

	user := &models.User{
		Username:     username,
		PasswordHash: hashedPassword,
	}

	err = s.db.Create(user).Error
	if err != nil {
		return err
	}

	log.Printf("✅ 已创建默认管理员账号: %s", username)
	return nil
}

// _ = fmt 用于开发日志输出
var _ = fmt.Sprintf
