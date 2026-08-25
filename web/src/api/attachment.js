// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

import request from './request'

// 获取邮件附件列表
export function getAttachmentsByMailId(mailId) {
  return request.get(`/attachments/mail/${mailId}`)
}
