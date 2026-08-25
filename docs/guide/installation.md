# 安装部署

Cosmo Mail 仅提供原生二进制部署，不包含容器或 NAS 专用安装包。

## 一键安装（Linux / macOS）

```bash
curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh | sudo bash
```

安装完成后：

```bash
cosmomail status
cosmomail logs
cosmomail restart
cosmomail update
```

默认监听 `0.0.0.0:8080`，数据保存在 `/var/lib/cosmomail`。

## 手动安装

从 Release 下载对应平台的文件（Linux x86_64 为 `cosmomail`，ARM 为 `cosmomail-arm` 或 `cosmomail-arm64`），赋予执行权限：

```bash
chmod +x cosmomail
COSMOMAIL_ENV=production \
COSMOMAIL_DSN=/var/lib/cosmomail/data/cosmomail.db \
./cosmomail
```

systemd 示例位于 `server/cosmomail.service`。

## Windows

下载 `cosmomail.exe`，在 PowerShell 中运行：

```powershell
$env:COSMOMAIL_ENV = "production"
$env:COSMOMAIL_DSN = "data/cosmomail.db"
.\cosmomail.exe
```

## 配置

常用变量：

| 变量 | 默认值 | 说明 |
|---|---:|---|
| `COSMOMAIL_PORT` | `8080` | Web 服务端口 |
| `COSMOMAIL_DSN` | `data/cosmomail.db` | SQLite 数据库路径 |
| `COSMOMAIL_POLL_INTERVAL` | `60` | IDLE 校验及降级轮询间隔（秒） |
| `COSMOMAIL_IDLE_ENABLED` | `true` | 启用 IMAP IDLE |
| `COSMOMAIL_MAX_CONCURRENT` | `10` | 最大同步并发数 |
| `COSMOMAIL_SYNC_BATCH_SIZE` | `50` | 单次同步处理上限 |

完整示例见项目根目录 `.env.example`。

## 反向代理

SSE 路径 `/api/v1/mails/stream` 必须关闭响应缓冲，并配置长连接读取超时。
