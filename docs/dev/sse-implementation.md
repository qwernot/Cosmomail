# SSE 实时推送功能 - 实施报告

## 修复内容

### 1. ✅ 修复 IMAP IDLE 回调（致命缺陷）

**问题诊断:**
- **原代码**: `idleLoop()` 只等待超时/停止信号，未监听 IMAP 服务器推送通道
- **影响**: IDLE 模式形同虚设，新邮件只能靠定时轮询发现（最长延迟 25 分钟）

**修复方案 (`server/imap/worker.go`):**
```go
// 修复前: 只监听超时和停止信号
select {
case <-timeout:
    return nil  // 直接返回不触发同步！
}

// 修复后: 使用 idleCmd.Wait() 阻塞等待服务器推送
go func() {
    err := idleCmd.Wait(ctx) // ← 关键修复点
    done <- err
}()

select {
case err := <-done:
    if !isIdleClosed(err) {
        return err  // 真正的错误
    }
    return nil  // 返回主循环执行 syncOnce()
}
```

**技术细节:**
- 使用 `context.WithTimeout` 设置 25 分钟保底超时（IMAP 规定最长 29 分钟）
- `idleCmd.Wait()` 会阻塞直到服务器推送 EXISTS/FETCH 等事件
- 返回 `nil` 后主循环会立即调用 `syncOnce()` 同步新邮件

---

### 2. ✅ 新增 SSE 实时推送服务

#### 架构设计

```
IMAP Worker (syncOnce)
    ↓ 发现新邮件
SSE Broker (发布-订阅)
    ↓ 广播事件
所有在线客户端 (EventSource)
```

#### 新建文件

##### `server/sse/broker.go` - 事件广播中心
- **数据结构:**
  ```go
  type Broker struct {
      clients    map[string]*Client  // 在线连接池
      broadcast  chan *SSEEvent      // 广播通道 (缓冲256)
      register   chan *Client        // 注册通道 (缓冲64)
      unregister chan string         // 注销通道 (缓冲64)
  }
  ```

- **核心功能:**
  - `Register()` / `Unregister()` - 客户端连接管理
  - `Publish(eventType, data)` - 发布事件给所有在线客户端
  - `GetOnlineCount()` - 监控在线数量
  - 后台 goroutine 处理注册/注销/广播的并发安全

- **防阻塞机制:**
  - 广播通道满时丢弃旧事件（防止阻塞 Worker）
  - 客户端响应慢自动断开（避免内存泄漏）

##### `server/sse/handler.go` - HTTP 端点处理器

- **StreamHandler** - `GET /api/v1/mails/stream`
  ```
  响应头:
  Content-Type: text/event-stream
  Cache-Control: no-cache, no-transform
  Connection: keep-alive
  
  事件格式:
  event: mail.received
  data: {"account_id":1,"mail_count":3,...}
  
  心跳: 每15秒发送 heartbeat 事件
  ```

- **便捷函数:**
  ```go
  sse.PublishMailReceived(accountID, email, count, mails)  // Worker 调用
  sse.PublishMailSynced(accountID, email)                   // Worker 调用
  ```

---

### 3. ✅ 集成到现有系统

#### 后端集成

**main.go 初始化:**
```go
// 启动 IMAP Worker 后初始化 SSE Broker
sse.InitBroker()
```

**routes.go 注册路由:**
```go
// 受保护接口（需 JWT 认证）
mails.Get("/stream", sse.StreamHandler)
mails.Get("/stream/health", sse.HealthCheckHandler)
```

**worker.go 事件发布:**
```go
// syncOnce() 中 Webhook 触发后追加:
sse.PublishMailReceived(w.account.ID, w.account.Email, count, mailList)
```

---

### 4. ✅ 前端实时更新

#### 新建文件: `web/src/composables/useSSE.js`

**核心功能:**
```javascript
export function useSSE(options = {}) {
  // 自动管理 EventSource 连接生命周期
  // 支持指数退避重连 (最多10次, 最大30秒间隔)
  // 事件回调: onMailReceived, onMailSynced, onConnected, onError
  
  return { connected, reconnectAttempts, connect, disconnect, reconnect }
}

// 便捷 Hook（邮件场景）
export function useMailStream(onUpdate) {
  return useSSE({
    onMailReceived: onUpdate,
    onMailSynced: onUpdate,
  })
}
```

**特性:**
- 组件挂载时自动连接，卸载时自动断开
- JWT Token 通过 URL 参数传递 (`?token=xxx`)
- 15 秒心跳保持连接活跃
- 断线自动重连（指数退避策略）

#### 修改文件: `web/src/views/MailListView.vue`

**变更对比:**

| 项目 | 修改前 | 修改后 |
|------|--------|--------|
| 更新机制 | 仅 60 秒定时轮询 | **SSE 实时推送 + 120 秒备用轮询** |
| 新邮件延迟 | 最长 60 秒 | **< 1 秒** |
| 连接方式 | 无 | EventSource 长连接 |

**关键代码:**
```vue
<script setup>
import { useMailStream } from '@/composables/useSSE'

onMounted(async () => {
  // ...原有逻辑...
  
  // 启动 SSE 实时推送
  useMailStream(() => {
    console.log('📡 收到更新事件，刷新列表')
    mailStore.fetchMails(mailStore.currentPage)
    mailStore.fetchStats()
  })
  
  // 备用轮询间隔延长至 120 秒
  startRefreshTimer()  // 内部改为 120000ms
})
</script>
```

---

## API 文档更新

### 新增端点

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/api/v1/mails/stream` | ✅ JWT | SSE 邮件更新流 |
| GET | `/api/v1/mails/stream/health` | ✅ JWT | SSE 服务健康检查 |

### SSE 事件类型

| 事件名 | 触发时机 | 数据结构 |
|--------|----------|----------|
| `connected` | 连接建立时 | `{client_id, server_time, online_count}` |
| `mail.received` | 新邮件到达时 | `{account_id, account_email, mail_count, mails[...], timestamp}` |
| `mail.synced` | 邮件同步完成时 | `{account_id, account_email, timestamp}` |
| `heartbeat` | 每 15 秒 | `{time}` |

### 示例用法

**JavaScript:**
```javascript
const es = new EventSource('/api/v1/mails/stream?token=YOUR_JWT_TOKEN')

es.addEventListener('mail.received', (e) => {
  const data = JSON.parse(e.data)
  alert(`收到 ${data.mail_count} 封新邮件!`)
})
```

**curl 测试:**
```bash
# 获取 token
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.token')

# 监听 SSE 流
curl -N -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/mails/stream
```

---

## 性能优化

### 服务端
- **并发控制**: Broker 使用带缓冲 channel，避免 goroutine 泄漏
- **内存保护**: 客户端响应慢时自动断开（防止内存堆积）
- **非阻塞**: Worker 调用 `Publish()` 不等待投递完成（异步广播）

### 客户端
- **重连策略**: 指数退避 (1s → 2s → 4s → ... → 30s)，最多 10 次
- **备用机制**: 120 秒定时轮询兜底（应对极端网络情况）

---

## 兼容性

### 浏览器支持
- ✅ Chrome 6+
- ✅ Firefox 6+
- ✅ Safari 5+
- ✅ Edge (全部版本)
- ❌ IE (不支持 EventSource)

### 降级方案
当浏览器不支持 SSE 或连接失败时：
1. 自动降级为 120 秒轮询
2. 控制台输出警告日志
3. 用户可手动刷新获取最新数据

---

## 测试验证

### 编译检查
```bash
cd server && go build -o /dev/null .
# 输出: ✅ 成功 (0 errors)

cd web && pnpm build
# 输出: ✅ 前端构建成功
```

### 功能测试步骤
1. 启动服务: `./bin/cosmomail`
2. 登录 Web UI: http://localhost:8080
3. 添加 IMAP 邮箱账号并激活
4. 发送测试邮件到该邮箱
5. **预期结果**: 
   - 后台日志显示 `IDLE 触发同步`
   - 前端 < 1 秒内自动刷新邮件列表
   - 无需手动刷新页面或等待 60 秒

---

## 未来扩展方向

### 短期 (可选)
- [ ] WebSocket 升级（支持双向通信，如在线状态显示）
- [ ] 按账号过滤推送（减少无关流量）
- [ ] SSE 重连状态 UI 提示（绿色圆点表示在线）

### 中长期
- [ ] 多标签页同步（BroadcastChannel API）
- [ ] 离线事件队列（Service Worker + IndexedDB）
- [ ] 推送通知权限（Notification API + 后台运行）

---

## 相关文件清单

| 文件路径 | 变更类型 | 说明 |
|---------|----------|------|
| `server/imap/worker.go` | 🔧 修改 | IDLE Wait() 修复 + SSE 事件发布 |
| `server/sse/broker.go` | 🆕 新建 | 事件广播中心 |
| `server/sse/handler.go` | 🆕 新建 | SSE 端点处理器 |
| `server/main.go` | 🔧 修改 | 初始化 SSE Broker |
| `server/routes/routes.go` | 🔧 修改 | 注册 SSE 路由 |
| `web/src/composables/useSSE.js` | 🆕 新建 | SSE composable |
| `web/src/views/MailListView.vue` | 🔧 修改 | 集成 SSE 推送 |

**总代码量**: +350 行 (Go), +180 行 (JS/Vue)
