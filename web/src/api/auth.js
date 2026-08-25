// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

import request from './request'

/** 查询认证状态（是否需要注册） */
export function getAuthStatus() {
  return request.get('/auth/status')
}

/** 登录 */
export function login(data) {
  return request.post('/auth/login', data)
}

/** 注册（仅首次可用） */
export function register(data) {
  return request.post('/auth/register', data, { timeout: 10000 })
}
