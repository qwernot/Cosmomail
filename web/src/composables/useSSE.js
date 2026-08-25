// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

import { ref, onMounted, onUnmounted } from 'vue'

/**
 * 从 localStorage 获取认证 Token
 */
function getToken() {
  return localStorage.getItem('cosmomail-token')
}

/**
 * SSE 实时推送 Composable
 * 
 * 用于接收服务器端的邮件更新事件，替代轮询机制
 * 
 * @param {Object} options - 配置选项
 * @param {Function} options.onMailReceived - 新邮件到达回调
 * @param {Function} options.onMailSynced - 同步完成回调
 * @param {Function} options.onConnected - 连接成功回调
 * @param {Function} options.onDisconnected - 断开连接回调
 * @param {Function} options.onError - 错误回调
 * @returns {Object} SSE 控制方法和状态
 */
export function useSSE(options = {}) {
  const eventSource = ref(null)
  const connected = ref(false)
  const connectionMode = ref('unknown') // 'sse' | 'polling' | 'unknown'
  const reconnectAttempts = ref(0)
  const maxReconnectAttempts = 5 // 降低重试次数，更快触发 fallback
  const reconnectDelayBase = 1000 // 基础重连延迟（毫秒）
  
  let reconnectTimer = null
  let hasFallenBack = false // 是否已触发回退
  let intentionalClose = false // 是否为预期内的断开（如探测完成后主动关闭）

  /**
   * 建立 SSE 连接
   */
  function connect() {
    if (hasFallenBack) return // 已回退，不再尝试
    if (eventSource.value) {
      disconnect()
    }

    intentionalClose = false // 重置：新连接的断开都视为异常（除非再次调用 disconnect）

    const token = getToken()
    if (!token) {
      console.warn('[useSSE] 未找到认证 token，延迟连接')
      setTimeout(connect, 1000)
      return
    }

    // 构建带认证的 SSE URL
    const baseUrl = import.meta.env.VITE_API_BASE_URL || ''
    const url = `${baseUrl}/api/v1/mails/stream?token=${encodeURIComponent(token)}`

    try {
      const es = new EventSource(url, { withCredentials: true })

      es.addEventListener('connected', (event) => {
        const data = JSON.parse(event.data)
        connected.value = true
        connectionMode.value = 'sse'
        reconnectAttempts.value = 0

        if (typeof options.onConnected === 'function') {
          options.onConnected(data)
        }
      })

      // 新邮件到达事件
      es.addEventListener('mail.received', (event) => {
        try {
          const data = JSON.parse(event.data)
          if (typeof options.onMailReceived === 'function') {
            options.onMailReceived(data)
          }
        } catch (e) {
          console.error('[useSSE] 解析 mail.received 事件失败:', e)
        }
      })

      // 邮件同步完成事件
      es.addEventListener('mail.synced', (event) => {
        try {
          const data = JSON.parse(event.data)
          if (typeof options.onMailSynced === 'function') {
            options.onMailSynced(data)
          }
        } catch (e) {
          console.error('[useSSE] 解析 mail.synced 事件失败:', e)
        }
      })

      // 心跳事件
      es.addEventListener('heartbeat', (event) => {
        // 保持连接活跃（可选：取消注释以调试）
        // console.log('[useSSE] 💓 心跳', event.data)
      })

      es.onerror = (error) => {
        // 预期内的断开（如探测完成后的主动关闭），静默忽略
        if (intentionalClose) return

        connected.value = false

        if (typeof options.onError === 'function') {
          options.onError(error)
        }

        // 检查是否需要触发回退
        if (reconnectAttempts.value >= maxReconnectAttempts - 1) {
          hasFallenBack = true
          connectionMode.value = 'polling'
          disconnect()
          if (typeof options.onFallback === 'function') {
            options.onFallback()
          }
          return
        }

        // 自动重连
        if (reconnectAttempts.value < maxReconnectAttempts) {
          scheduleReconnect()
        } else {
          if (typeof options.onDisconnected === 'function') {
            options.onDisconnected()
          }
        }
      }

      eventSource.value = es
    } catch (e) {
      console.error('[useSSE] 创建 EventSource 失败:', e)
      
      if (reconnectAttempts.value < maxReconnectAttempts && !hasFallenBack) {
        scheduleReconnect()
      }
    }
  }

  /**
   * 安排重连（指数退避策略）
   */
  function scheduleReconnect() {
    reconnectAttempts.value++
    const delay = Math.min(
      reconnectDelayBase * Math.pow(2, reconnectAttempts.value - 1),
      30000 // 最大 30 秒
    )

    reconnectTimer = setTimeout(() => {
      connect()
    }, delay)
  }

  /**
   * 断开 SSE 连接
   */
  function disconnect() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }

    intentionalClose = true // 标记为预期断开

    if (eventSource.value) {
      eventSource.value.close()
      eventSource.value = null
      connected.value = false
    }
  }

  /**
   * 手动重新连接
   */
  function reconnect() {
    reconnectAttempts.value = 0
    disconnect()
    connect()
  }

  // 组件挂载时自动连接
  onMounted(() => {
    connect()
  })

  // 组件卸载时断开连接
  onUnmounted(() => {
    disconnect()
  })

  return {
    eventSource,
    connected,
    connectionMode,
    reconnectAttempts,
    connect,
    disconnect,
    reconnect,
  }
}

/**
 * 使用默认配置的邮件 SSE Hook（便捷方法）
 * 
 * @param {Function} onMailUpdate - 邮件更新时的回调函数
 * @param {Object} extraOptions - 额外配置
 * @param {Function} extraOptions.onFallback - SSE 失败后的回退回调（启动轮询）
 * @returns {Object} SSE 控制方法和状态
 */
export function useMailStream(onMailUpdate, extraOptions = {}) {
  return useSSE({
    onMailReceived: onMailUpdate,
    onMailSynced: onMailUpdate,
    onError: () => {
      // 连接中断由内部自动重连处理
    },
    onFallback: () => {
      if (typeof extraOptions.onFallback === 'function') {
        extraOptions.onFallback()
      }
    },
  })
}
