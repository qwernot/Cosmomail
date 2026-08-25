# 快速开始

## 1. 安装

Linux 或 macOS：

```bash
curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh | sudo bash
```

Windows 请下载 Release 中的 `cosmomail-windows-amd64.exe` 直接运行。

## 2. 打开界面

浏览器访问 `http://服务器地址:8080`，首次打开时创建管理员账号。

## 3. 添加邮箱

进入“邮箱账号”，选择服务商或手动填写 IMAP/POP3 与 SMTP 配置。推荐使用 IMAP；支持 IDLE 的服务器可以实时发现新邮件。

## 4. 管理服务

```bash
cosmomail status
cosmomail logs
cosmomail restart
cosmomail doctor
```
