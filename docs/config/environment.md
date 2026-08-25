# 环境变量参考

所有环境变量均为可选，不设置则使用默认值。

可通过以下方式设置：

```bash
# 方式一：命令行导出
export COSMOMAIL_PORT=9090
./cosmomail

# 方式二：.env 文件（放置在程序运行目录下）
echo "COSMOMAIL_PORT=9090" > .env
./cosmomail
```

## 运行模式

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COSMOMAIL_ENV` | 空（开发模式） | 设为 `production` 关闭 SQL 日志并启用 release 模式 |

## 服务配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COSMOMAIL_PORT` | `8080` | HTTP 监听端口 |
| `COSMOMAIL_HOST` | `0.0.0.0` | HTTP 监听地址 |
| `COSMOMAIL_DSN` | `data/cosmomail.db` | SQLite 数据库文件路径（相对于运行目录）|
| `COSMOMAIL_CORS_ORIGINS` | 允许所有来源 | CORS 白名单（逗号分隔）|

**CORS 示例**：

```bash
# 允许多个域名
export COSMOMAIL_CORS_ORIGINS="https://app.example.com,https://web.example.com"

# 允许所有（默认行为）
export COSMOMAIL_CORS_ORIGINS="*"
```

## IMAP 同步配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COSMOMAIL_POLL_INTERVAL` | `300`（5 分钟）| IMAP 定时轮询间隔（秒），最低 10 秒 |
| `COSMOMAIL_IDLE_ENABLED` | `false` | 可选启用 IMAP IDLE；默认关闭并对所有邮箱执行 5 秒增量轮询 |
| `COSMOMAIL_MAX_CONCURRENT` | `10` | IMAP 最大并发连接数 |
| `COSMOMAIL_SYNC_BATCH_SIZE` | `50` | 每次同步拉取邮件数量上限 |

## 附件缓存配置（混合模式）

> 以下变量控制附件的缓存策略：**小文件立即缓存 + 大文件懒加载按需下载**。
> 单位统一为 **MB**，直接填数字即可。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COSMOMAIL_AUTO_CACHE` | `false` | 启用**自动缓存**（懒加载的附件在用户首次下载后异步缓存到本地）|
| `COSMOMAIL_CACHE_THRESHOLD` | `2` | 缓存阈值（MB）。小于此值的附件同步时**立即缓存**；大于此值的仅存元数据，用户下载时从 IMAP 按需获取 |
| `COSMOMAIL_MIN_DISK_FREE` | `1024` | 最小保留磁盘空间（MB）。剩余空间低于此值时停止缓存新附件 |
| `COSMOMAIL_MAX_ATTACHMENT_SIZE` | `50` | 单附件大小上限（MB）。超过此值的附件直接跳过不处理 |
| `COSMOMAIL_CACHE_EXPIRE_DAYS` | `30` | 缓存过期天数。超期未访问的缓存将被自动清理释放空间 |

### 自动缓存工作流程

```
用户点击下载附件
       ↓
检查 COSMOMAIL_AUTO_CACHE == true ?
   ├─ NO → 直接流式传输给用户（不缓存）
   └─ YES → 检查条件
             ├─ 已缓存？→ 跳过（直接返回本地）
             ├─ 超过 CACHE_THRESHOLD？→ 跳过（仅流式传输）
             ├─ 超过 MAX_ATTACHMENT_SIZE？→ 跳过
             ├─ 磁盘空间不足？→ 跳过 + 日志警告
             └─ ✅ 全部通过 → io.TeeReader 边传边写
                              ├─ HTTP 响应（用户立即收到文件）
                              └─ 异步写入本地磁盘（下次秒传）
```

### 配置示例

```bash
# 生产环境推荐（30GB VPS）
export COSMOMAIL_AUTO_CACHE=true          # 开启自动缓存
export COSMOMAIL_CACHE_THRESHOLD=5        # 5MB 以下立即缓存
export COSMOMAIL_MIN_DISK_FREE=5120       # 保留 5GB 空间
export COSMOMAIL_MAX_ATTACHMENT_SIZE=100  # 最大允许 100MB
export COSMOMAIL_CACHE_EXPIRE_DAYS=30     # 30 天清理

# 小机器保守模式
export COSMOMAIL_AUTO_CACHE=false         # 不缓存，纯懒加载
export COSMOMAIL_CACHE_THRESHOLD=0        # 所有附件都懒加载
export COSMOMAIL_MIN_DISK_FREE=512        # 保留 512MB
```

::: tip 提示
- 默认 `COSMOMAIL_AUTO_CACHE=false`，即**不开启自动缓存**，所有大附件都是纯懒加载模式，不占用额外磁盘空间
- 只有明确设置 `COSMOMAIL_AUTO_CACHE=true` 才会启用首次下载后的自动缓存功能
- 懒加载模式下，每次下载都需要临时建立 IMAP 连接（~100ms 开销），但对大多数场景可忽略
:::

## 安全密钥

> 以下密钥**默认自动生成**并持久化到数据库，通常无需手动配置。
> 如需在多实例间共享密钥或确保重启后密钥不变，可通过环境变量显式指定（优先级高于数据库存储值）。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COSMOMAIL_JWT_SECRET` | 自动生成 | JWT 签名密钥 |
| `COSMOMAIL_ENCRYPT_KEY` | 自动生成 | AES-256-GCM 加密密钥（用于加密存储邮箱密码）|

### 密钥加载优先级

```
环境变量 > 数据库存储值 > 首次启动自动生成
```

1. **首次启动**：若未设置环境变量，系统自动生成随机密钥并存入数据库
2. **后续启动**：
   - 未设置环境变量 → 从数据库读取
   - 设置了环境变量且与数据库不同 → 使用环境变量值，并同步更新数据库

::: warning 生产部署建议
生产环境建议显式设置 `COSMOMAIL_JWT_SECRET` 和 `COSMOMAIL_ENCRYPT_KEY`，避免因数据库丢失导致无法解密已存储的邮箱密码。密钥长度建议 ≥ 32 字符。
:::

## 完整示例

```bash
#!/bin/bash
# production.env

# 运行模式
export COSMOMAIL_ENV=production

# 监听配置
export COSMOMAIL_HOST=0.0.0.0
export COSMOMAIL_PORT=8080

# 数据库
export COSMOMAIL_DSN=/app/data/cosmomail.db

# CORS（按需调整）
export COSMOMAIL_CORS_ORIGINS="https://mail.yourdomain.com"

# IMAP 同步调优
export COSMOMAIL_POLL_INTERVAL=180
export COSMOMAIL_MAX_CONCURRENT=20

# 安全密钥（生产环境必设！）
export COSMOMAIL_JWT_SECRET="your-super-secret-jwt-key-here"
export COSMOMAIL_ENCRYPT_KEY="your-32-byte-encryption-key-1234567890"
```

```bash
source production.env && ./cosmomail
```
