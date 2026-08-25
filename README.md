<div align="center">

<img src="./public/images/icon_512.png" alt="Cosmo Mail" width="128" height="128">

# Cosmo Mail

快速、私有的多邮箱统一管理平台。

</div>

Cosmo Mail 使用 Go、SQLite 和 Vue 3 构建，支持 IMAP IDLE、UID 增量同步、POP3 UIDL、SMTP 发信、SSE/Web Push 与 Webhook。邮件和凭据由用户自行托管。

## 快速部署

```bash
curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh | sudo bash
```

安装后使用统一的 `cosmomail` 命令：

```bash
cosmomail status
cosmomail start
cosmomail stop
cosmomail restart
cosmomail update
cosmomail logs
cosmomail doctor
cosmomail uninstall
```

## 本地开发

需要 Go 1.25+、Node.js 20+ 和 pnpm/npm。

```bash
./dev.sh start
```

生产构建：

```bash
./build.sh
```

构建产物位于 `bin/`，可通过 `COSMOMAIL_*` 环境变量配置运行参数，示例见 `.env.example`。

## License

Cosmo Mail 基于 AGPL-3.0-or-later 发布。该项目由原 AGPL 代码继续开发；原作者版权声明保留在源码与许可证中。通过网络向用户提供服务时，需要向用户提供对应版本的完整源代码。

[完整许可证](./LICENSE)
