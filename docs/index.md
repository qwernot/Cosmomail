---
layout: home

hero:
  name: Cosmo Mail
  text: 所有邮箱，一处抵达
  tagline: 自托管的多邮箱统一收件箱。数据留在自己的服务器上，邮件、附件、通知与自动化集中管理。
  image:
    src: /icon.png
    alt: Cosmo Mail
  actions:
    - theme: brand
      text: 立即部署
      link: /guide/getting-started
    - theme: alt
      text: 查看功能
      link: /guide/features
    - theme: alt
      text: GitHub
      link: https://github.com/qwernot/Cosmomail

features:
  - icon: 🌌
    title: 多邮箱归一
    details: 在一个界面管理 QQ、Outlook、Gmail、163、企业邮箱及其他标准 IMAP/POP3 邮箱。
  - icon: ⚡
    title: 增量收信
    details: 使用 UID 游标只获取新增邮件；支持 IMAP IDLE，并以可靠轮询补偿服务商漏发通知。
  - icon: 🪐
    title: 单文件运行
    details: 前端与后端打包为一个原生可执行文件，SQLite 本地存储，不依赖 Docker 或 NAS 套件。
  - icon: 🔐
    title: 数据自主
    details: 邮件、附件和凭据保存在自己的设备；凭据加密存储，支持代理与 Outlook OAuth2。
  - icon: 🛰️
    title: 通知与自动化
    details: 提供 SSE、Web Push 和可自定义的 Webhook，把新邮件接入企业微信或自动化工作流。
  - icon: 📱
    title: 全端 PWA
    details: 响应式界面适配桌面和手机，可安装到主屏幕，并支持深色主题。
---

## 三步开始

### 1. 下载部署脚本

```bash
curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh -o cosmomail.sh
chmod +x cosmomail.sh
```

### 2. 安装并启动

```bash
sudo ./cosmomail.sh install
```

### 3. 打开管理界面

访问 `http://服务器地址:8080`，创建管理员账号，然后添加你的邮箱。

::: tip 正式使用
建议绑定域名并配置 HTTPS 后，再录入正式邮箱凭据。
:::

## 日常管理

```bash
cosmomail status      # 查看运行状态
cosmomail logs        # 查看实时日志
cosmomail restart     # 重启服务
cosmomail update      # 更新到最新版
cosmomail doctor      # 环境健康检查
```

## 技术架构

| 层级 | 技术 |
|---|---|
| 后端 | Go、Fiber、GORM、SQLite、go-imap/v2 |
| 前端 | Vue 3、Vite、Pinia、Vue Router |
| 客户端 | PWA、Service Worker、响应式 Web UI |
| 通知 | SSE、Web Push、Webhook |
| 部署 | Linux systemd、macOS、Windows 原生二进制 |

全部源代码、版本发布和问题跟踪都在 [Cosmo Mail GitHub 仓库](https://github.com/qwernot/Cosmomail)。
