// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

/**
 * 用法:
 *   import { useToast } from '@/composables/useToast'
 *   const toast = useToast()
 *
 *   // Toast
 *   toast.success('操作成功')
 *   toast.error('出错了')
 *   toast.warning('警告')
 *   toast.info('提示信息')
 *
 *   // Confirm (返回 Promise<boolean>)
 *   const ok = await toast.confirm('确定删除吗？')
 */

let toastState = null
let confirmState = null

export function initToast(state) {
  toastState = state
}

export function initConfirm(state) {
  confirmState = state
}

export function useToast() {
  // --- Toast ---
  const show = (message, type = 'info', duration = 3000) => {
    if (!toastState) {
      console.warn('[useToast] 未初始化，回退到 console')
      console.log(`[${type}] ${message}`)
      return
    }
    const id = Date.now() + Math.random()
    const item = { id, message, type, duration }
    toastState.items.value = [...toastState.items.value, item]
    if (duration > 0) {
      setTimeout(() => remove(id), duration)
    }
    return id
  }

  const remove = (id) => {
    if (!toastState) return
    toastState.items.value = toastState.items.value.filter(t => t.id !== id)
  }

  // --- Confirm ---
  const confirm = (message, title = '确认操作') => new Promise((resolve) => {
    if (!confirmState) {
      console.warn('[useToast] confirm 未初始化，回退到 window.confirm')
      resolve(window.confirm(message))
      return
    }
    const id = Date.now() + Math.random()
    const dialog = { id, message, title, resolve }
    confirmState.dialogs.value = [...confirmState.dialogs.value, dialog]
  })

  return {
    show,
    success: (msg, dur) => show(msg, 'success', dur),
    error: (msg, dur) => show(msg, 'error', dur),
    warning: (msg, dur) => show(msg, 'warning', dur),
    info: (msg, dur) => show(msg, 'info', dur),
    remove,
    confirm,
  }
}
