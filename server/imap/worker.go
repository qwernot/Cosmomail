// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026  magiccode (魔法代码)

package imap

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"cosmomail/config"
	"cosmomail/models"
	"cosmomail/notifier"
	pop3pkg "cosmomail/pop3"
	"cosmomail/sse"

	"github.com/emersion/go-imap/v2/imapclient"
	"gorm.io/gorm"
)

// WorkerPool 管理所有邮箱账号的后台同步协程
type WorkerPool struct {
	db         *gorm.DB
	config     *config.Config
	workers    map[uint]*AccountWorker // accountID -> worker
	mu         sync.RWMutex
	shutdown   int32 // 原子标志：1=关闭中
	shutdownCh chan struct{}
	wg         sync.WaitGroup
	sem        chan struct{} // 并发信号量
}

// TriggerSync coalesces a manual sync request into the account's worker.
func (p *WorkerPool) TriggerSync(accountID uint) bool {
	p.mu.RLock()
	w, ok := p.workers[accountID]
	p.mu.RUnlock()
	if !ok {
		return false
	}
	w.TriggerSync()
	return true
}

var (
	globalPool   *WorkerPool
	globalPoolMu sync.RWMutex
)

// idleVerifiedServers 已确认支持 IMAP IDLE 的服务器白名单
// 只有经过验证的服务器才会尝试IDLE，未知服务器首次会尝试并记录结果
var idleVerifiedServers = map[string]bool{
	"imap.gmail.com":        true, // Gmail - RFC2177 标准实现
	"imap.mail.yahoo.com":   true, // Yahoo Mail - 支持IDLE
	"outlook.office365.com": true, // Outlook/Exchange Online - 支持IDLE
}

// pollingOnlyServers 接受 IDLE 命令但实测可能不发送 EXISTS 通知的服务器。
// 对这些服务器直接使用短周期增量轮询，避免邮件一直等到手动同步才出现。
var pollingOnlyServers = map[string]bool{
	"imap.qq.com":        true,
	"imap.exmail.qq.com": true,
}

// idleLearnedUnsupported 运行时学习到的、已确认不支持IDLE的服务器（全局共享）
var (
	idleLearnedUnsupported = make(map[string]bool)
	idleLearnMu            sync.RWMutex // 保护并发访问
)

// GlobalPool exposes the worker pool for external packages (services/handlers)
// Returns nil if workers haven't been started yet
func GlobalPool() *WorkerPool {
	globalPoolMu.RLock()
	defer globalPoolMu.RUnlock()
	return globalPool
}

// StartWorkers 启动所有活跃邮箱的后台同步 Worker（程序启动时调用）
func StartWorkers(db *gorm.DB, cfg *config.Config) {
	pool := &WorkerPool{
		db:         db,
		config:     cfg,
		workers:    make(map[uint]*AccountWorker),
		shutdownCh: make(chan struct{}),
		sem:        make(chan struct{}, cfg.IMAP.MaxConcurrent),
	}
	globalPoolMu.Lock()
	globalPool = pool
	globalPoolMu.Unlock()

	// 查询所有活跃的邮箱账号
	var accounts []models.MailAccount
	if err := db.Where("status = ?", "active").Find(&accounts).Error; err != nil {
		log.Printf("❌ 查询邮箱账号失败: %v", err)
		return
	}

	if len(accounts) == 0 {
		log.Println("📭 没有活跃的邮箱账号")
		return
	}

	log.Printf("🚀 启动 %d 个邮箱同步 Worker...", len(accounts))

	for i := range accounts {
		pool.StartWorker(&accounts[i])
	}
}

// StopWorkers 优雅关闭所有 Worker
func StopWorkers() {
	pool := GlobalPool()
	if pool == nil {
		return
	}
	atomic.StoreInt32(&pool.shutdown, 1)
	close(pool.shutdownCh)

	pool.mu.RLock()
	for _, w := range pool.workers {
		w.Stop()
	}
	pool.mu.RUnlock()

	pool.wg.Wait()
	log.Println("🛑 所有 IMAP Worker 已停止")
}

// StartWorker 为单个邮箱账号启动同步协程
func (p *WorkerPool) StartWorker(account *models.MailAccount) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// 如果已有该账号的 Worker，先停掉旧的
	if existing, ok := p.workers[account.ID]; ok {
		existing.Stop()
	}

	w := NewAccountWorker(account, p.db, p.config, p.sem, p.shutdownCh)
	p.workers[account.ID] = w

	p.wg.Add(1)
	go func() {
		defer p.wg.Done()
		w.Run()
	}()

	log.Printf("▶️  Worker 启动: %s (%s)", account.Email, account.Name)
}

// StopWorker 停止指定账号的 Worker
func (p *WorkerPool) StopWorker(accountID uint) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if w, ok := p.workers[accountID]; ok {
		w.Stop()
		delete(p.workers, accountID)
	}
}

// RestartWorker 重启指定账号的 Worker（配置变更后调用）
func (p *WorkerPool) RestartWorker(account *models.MailAccount) {
	p.StartWorker(account)
}

// AccountWorker 单个邮箱账号的同步 Worker
type AccountWorker struct {
	account         *models.MailAccount
	db              *gorm.DB
	config          *config.Config
	sem             chan struct{}
	shutdownCh      chan struct{}
	stopCh          chan struct{} // 该 Worker 的独立停止通道
	syncCh          chan struct{} // 手动/外部触发，容量1用于合并重复请求
	stopOnce        sync.Once
	idleUnsupported bool // 标记该账号是否不支持IDLE（避免重复尝试）
	activeMu        sync.Mutex
	activeIMAP      *IMAPClient
	activeSince     time.Time
}

const imapOperationTimeout = 2 * time.Minute

// NewAccountWorker 创建新的账号 Worker
func NewAccountWorker(account *models.MailAccount, db *gorm.DB, cfg *config.Config, sem chan struct{}, shutdownCh chan struct{}) *AccountWorker {
	w := &AccountWorker{
		account:    account,
		db:         db,
		config:     cfg,
		sem:        sem,
		shutdownCh: shutdownCh,
		stopCh:     make(chan struct{}),
		syncCh:     make(chan struct{}, 1),
	}
	host := strings.ToLower(strings.TrimSpace(account.ImapHost))
	if pollingOnlyServers[host] {
		w.idleUnsupported = true
		log.Printf("⚡ %s (%s) 使用 %d 秒快速增量轮询", account.Email, account.ImapHost, cfg.IMAP.PollInterval)
		return w
	}

	// 策略：默认尝试IDLE，除非已知该服务器不支持（通过运行时学习）
	// 不在白名单的服务器也会首次尝试IDLE，失败后自动标记为不支持
	if !idleVerifiedServers[host] {
		log.Printf("ℹ️  %s (%s) 未在IDLE支持列表中，将首次尝试IDLE（失败后将自动禁用）",
			account.Email, account.ImapHost)
	}

	return w
}

// Run 启动 Worker 主循环：先做一次全量同步，然后进入 IDLE（仅 IMAP）或轮询模式
func (w *AccountWorker) Run() {
	defer log.Printf("⏹️  Worker 退出: %s", w.account.Email)
	watchdogDone := make(chan struct{})
	defer close(watchdogDone)
	go w.watchdogLoop(watchdogDone)

	// 首次全量同步
	w.syncOnce()

	for {
		if w.shouldStop() {
			return
		}

		if w.isIMAP() && w.config.IMAP.IDLEEnabled && !w.isIDLEUnsupported() {
			if err := w.idleLoop(); err != nil {
				errMsg := strings.ToLower(err.Error())
				if strings.Contains(errMsg, "bad") || strings.Contains(errMsg, "not support") || strings.Contains(errMsg, "not allowed") {
					w.markIDLEUnsupported()
					log.Printf("⚠️  %s (%s) 不支持 IDLE，切换为可靠轮询: %v", w.account.Email, w.account.ImapHost, err)
				} else {
					log.Printf("⚠️  IDLE 异常 (%s): %v，30 秒后重连", w.account.Email, err)
					select {
					case <-time.After(30 * time.Second):
					case <-w.syncCh:
					case <-w.stopCh:
						return
					case <-w.shutdownCh:
						return
					}
				}
				continue
			}
			if w.shouldStop() {
				return
			}
			w.syncOnce()
			continue
		}

		timer := time.NewTimer(time.Duration(w.config.IMAP.PollInterval) * time.Second)
		select {
		case <-timer.C:
		case <-w.syncCh:
			if !timer.Stop() {
				<-timer.C
			}
		case <-w.stopCh:
			timer.Stop()
			return
		case <-w.shutdownCh:
			timer.Stop()
			return
		}
		w.syncOnce()
	}
}

func (w *AccountWorker) shouldStop() bool {
	select {
	case <-w.stopCh:
		return true
	case <-w.shutdownCh:
		return true
	default:
		return false
	}
}

// syncOnce 执行单次完整同步
func (w *AccountWorker) syncOnce() {
	// 获取并发令牌。多邮箱同时到信时必须排队，不能丢掉同步请求。
	select {
	case w.sem <- struct{}{}:
	case <-w.stopCh:
		return
	case <-w.shutdownCh:
		return
	}
	defer func() { <-w.sem }()

	// 重新从数据库获取最新账号信息（密码可能被更新）
	var fresh models.MailAccount
	if err := w.db.First(&fresh, w.account.ID).Error; err != nil {
		log.Printf("❌ 无法获取账号信息 (ID=%d): %v", w.account.ID, err)
		return
	}
	w.account = &fresh

	// 根据协议创建对应的邮件客户端
	client, err := NewMailClient(w.account, w.config)
	if err != nil {
		w.updateAccountStatus("error", err.Error())
		return
	}
	if imapClient, ok := client.(*IMAPClient); ok {
		w.setActiveIMAP(imapClient)
		defer w.clearActiveIMAP(imapClient)
		if deadlineErr := imapClient.SetDeadline(time.Now().Add(imapOperationTimeout)); deadlineErr != nil {
			client.Close()
			w.updateAccountStatus("error", fmt.Sprintf("设置 IMAP 操作超时失败: %v", deadlineErr))
			return
		}
	}
	defer client.Close()

	// 认证
	if err := client.Authenticate(); err != nil {
		w.updateAccountStatus("error", err.Error())
		return
	}

	// 根据协议选择对应的拉取器执行同步
	var count int
	var syncedIDs []uint // 本次同步成功入库的邮件ID（webhook精确推送用）
	if w.isIMAP() {
		// INBOX is latency-sensitive: notify the UI before the lower-priority Sent sync.
		imapClient := client.(*IMAPClient)
		fetcher := NewFetcher(w.db, w.config)
		count, err = fetcher.SyncMailbox(imapClient)
		if err == nil {
			if count > 0 {
				w.notifyNewMails(count, fetcher.SyncedMailIDs)
			}
			// 继续同步已发送文件夹（失败不阻止主流程）
			sentFetcher := NewFetcher(w.db, w.config)
			if sentCount, sentErr := sentFetcher.SyncSentMailbox(imapClient); sentErr == nil {
				count += sentCount
			}
		}
	} else {
		// POP3 同步
		pop3Client := client.(*pop3pkg.POP3Client)
		pop3Fetcher := pop3pkg.NewPOP3Fetcher(w.db, w.config)
		count, err = pop3Fetcher.SyncMailbox(pop3Client)
		syncedIDs = pop3Fetcher.SyncedMailIDs // POP3: 从 POP3Fetcher 获取精确ID
	}

	if err != nil {
		w.updateAccountStatus("error", err.Error())
		return
	}

	// 同步成功，更新状态和时间
	now := time.Now()
	w.db.Model(&models.MailAccount{}).Where("id = ?", w.account.ID).
		Updates(map[string]interface{}{
			"last_sync_at": now,
			"status":       "active",
			"error_msg":    "",
		})

	if !w.isIMAP() && count > 0 {
		w.notifyNewMails(count, syncedIDs)
	}
	if count > 0 {
		log.Printf("📬 %s 同步完成: 新增 %d 封邮件", w.account.Email, count)
	}
	// Let active clients refresh status even when there were only Sent changes.
	sse.PublishMailSynced(w.account.ID, w.account.Email)
}

func (w *AccountWorker) setActiveIMAP(client *IMAPClient) {
	w.activeMu.Lock()
	w.activeIMAP = client
	w.activeSince = time.Now()
	w.activeMu.Unlock()
}

func (w *AccountWorker) clearActiveIMAP(client *IMAPClient) {
	w.activeMu.Lock()
	if w.activeIMAP == client {
		w.activeIMAP = nil
		w.activeSince = time.Time{}
	}
	w.activeMu.Unlock()
}

// watchdogLoop is a second line of defence beyond socket deadlines. If a
// library call wedges while holding an internal lock, closing the raw TLS
// transport forces the command to unwind and lets the next poll reconnect.
func (w *AccountWorker) watchdogLoop(done <-chan struct{}) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			w.activeMu.Lock()
			client := w.activeIMAP
			activeSince := w.activeSince
			w.activeMu.Unlock()
			if client != nil && !activeSince.IsZero() && time.Since(activeSince) > imapOperationTimeout+15*time.Second {
				log.Printf("⏱️  IMAP 操作超时 (%s)，强制断开并重建连接", client.Account.Email)
				client.ForceClose()
			}
		case <-done:
			return
		case <-w.stopCh:
			return
		case <-w.shutdownCh:
			return
		}
	}
}

func (w *AccountWorker) notifyNewMails(count int, syncedIDs []uint) {
	if len(syncedIDs) == 0 {
		log.Printf("⚠️  %s 有新增邮件但无ID记录，跳过通知", w.account.Email)
		return
	}

	log.Printf("🔍 [WEBHOOK] 准备为 %d 个邮件ID发送通知: %v", len(syncedIDs), syncedIDs)

	// 验证：检查DB中这些ID是否真实存在
	var dbCount int64
	w.db.Table("mails").Where("id IN ?", syncedIDs).Count(&dbCount)
	log.Printf("🔍 [WEBHOOK] DB中实际存在的邮件数: %d (计划查 %d 封)", dbCount, len(syncedIDs))

	var latestMails []struct {
		ID       uint      `gorm:"column:id"`
		Subject  string    `json:"subject"`
		From     string    `json:"from"`
		To       string    `gorm:"column:to"` // 收件人
		Cc       string    `gorm:"column:cc"` // 抄送
		SentAt   time.Time `json:"sent_at"`
		TextBody string    `gorm:"column:text_body"` // 纯文本正文
		HTMLBody string    `gorm:"column:html_body"` // HTML 正文（fallback）
	}
	w.db.Table("mails").
		Select("id, subject, `from`, `to`, cc, sent_at, text_body, html_body").
		Where("id IN ?", syncedIDs).
		Order("sent_at DESC").
		Find(&latestMails)

	log.Printf("🔍 [WEBHOOK] DB查询返回 %d 封邮件 (预期 %d)", len(latestMails), len(syncedIDs))

	mailList := make([]map[string]interface{}, len(latestMails))
	for i, m := range latestMails {
		// 预览：优先纯文本，其次 HTML 去标签，截取前 200 字符
		preview := m.TextBody
		if preview == "" && m.HTMLBody != "" {
			preview = stripHTML(m.HTMLBody)
		}
		if len(preview) > 200 {
			preview = preview[:200] + "..."
		}
		mailList[i] = map[string]interface{}{
			"subject":   m.Subject,
			"from":      m.From,
			"to":        m.To,
			"cc":        m.Cc,
			"sent_at":   m.SentAt.Format("2006-01-02 15:04:05"),
			"preview":   preview,
			"text_body": m.TextBody,
			"html_body": m.HTMLBody,
		}
	}

	// 触发 Webhook 通知（每封邮件独立触发一次）
	nowTs := fmt.Sprintf("%d", time.Now().Unix())
	for _, mail := range mailList {
		notifier.TriggerByEvent(w.db, "mail.received", map[string]interface{}{
			"account_id":    w.account.ID,
			"account_email": w.account.Email,
			"account_name":  w.account.Name,
			"protocol":      w.account.Protocol,
			"subject":       mail["subject"],
			"from":          mail["from"],
			"to":            mail["to"],
			"cc":            mail["cc"],
			"sent_at":       mail["sent_at"],
			"preview":       mail["preview"],
			"text_body":     mail["text_body"],
			"html_body":     mail["html_body"],
			"timestamp":     nowTs,
		})
	}

	// 推送 SSE 实时事件给前端
	sse.PublishMailReceived(w.account.ID, w.account.Email, count, mailList)

	// 发送 Web Push 离线推送通知（通过 notifier 包桥接，避免循环依赖）
	notifier.SendPushNotification(
		1,
		fmt.Sprintf("📧 您有 %d 封新邮件", count),
		fmt.Sprintf("来自 %s", w.account.Email),
		map[string]interface{}{"account_id": w.account.ID},
	)
}

// isIMAP 判断当前账号是否为 IMAP 协议
func (w *AccountWorker) isIMAP() bool {
	return w.account.Protocol != "pop3" && w.account.Protocol != "pop3-no-ssl"
}

// isIDLEUnsupported 检查该账号的服务器是否已知不支持IDLE（本地 + 全局）
func (w *AccountWorker) isIDLEUnsupported() bool {
	if w.idleUnsupported {
		return true
	}

	// 检查全局学习列表
	idleLearnMu.RLock()
	defer idleLearnMu.RUnlock()
	return idleLearnedUnsupported[w.account.ImapHost]
}

// markIDLEUnsupported 将该服务器标记为不支持IDLE（写入全局共享内存）
func (w *AccountWorker) markIDLEUnsupported() {
	w.idleUnsupported = true

	// 写入全局学习列表，让其他同服务器的Worker也能受益
	idleLearnMu.Lock()
	defer idleLearnMu.Unlock()

	if !idleLearnedUnsupported[w.account.ImapHost] {
		idleLearnedUnsupported[w.account.ImapHost] = true
		log.Printf("📝 已将 %s 加入 IDLE 不支持黑名单", w.account.ImapHost)
	}
}

// idleLoop 进入 IDLE 监听循环，等待服务器推送新邮件通知
//
// go-imap/v2 的 IDLE 实现机制:
//   - Idle().Wait() 只在连接断开或手动 Close() 时返回
//   - 收到 EXISTS (新邮件) 不会让 Wait() 返回
//   - 必须通过 UnilateralDataHandler 回调检测新邮件到达
//
// 本函数采用"IDLE 短周期轮询"策略:
//  1. 启动 IDLE 并设置 Mailbox handler 监听 EXISTS 事件
//  2. 收到 EXISTS 后立即关闭 IDLE，返回主循环执行 syncOnce()
//  3. 如果 25 分钟无事件则自动重启 IDLE（IMAP 规定最长 29 分钟）
func (w *AccountWorker) idleLoop() error {
	// 创建带 UnilateralDataHandler 的 IMAP 客户端
	// 用于接收服务器的单方面数据推送 (EXISTS, FETCH, EXPUNGE 等)
	mailboxCh := make(chan struct{}, 1) // 非缓冲: 收到 EXISTS 时通知

	client, err := w.newIMAPClientWithHandler(mailboxCh)
	if err != nil {
		return err
	}
	defer client.Close()

	if err := client.Authenticate(); err != nil {
		return err
	}

	_, err = client.SelectINBOX()
	if err != nil {
		return err
	}

	// 进入 IDLE 模式
	log.Printf("🔄 IDLE 监听中: %s", w.account.Email)

	idleCmd, err := client.Client.Idle()
	if err != nil {
		return fmt.Errorf("IDLE 命令失败: %w", err)
	}

	// 等待以下任一事件:
	//   1. mailboxCh - 收到 EXISTS (新邮件到达)
	//   2. 25分钟超时 - IMAP 规定的安全重启间隔
	//   3. stopCh/shutdownCh - 停止信号
	select {
	case <-mailboxCh:
		// ⭐ 收到服务器推送的新邮件通知！
		idleCmd.Close()
		log.Printf("📬 IDLE 收到新邮件通知: %s", w.account.Email)
		return nil // 返回主循环执行 syncOnce()

	case <-time.After(w.idleRefreshInterval()):
		// 周期性退出 IDLE 做一次增量校验，补偿代理或服务器漏掉的通知。
		idleCmd.Close()
		log.Printf("⏰ IDLE 超时重启: %s", w.account.Email)
		return nil // 返回主循环重新进入 IDLE

	case <-w.stopCh:
		idleCmd.Close()
		log.Printf("⏹️  IDLE 停止信号: %s", w.account.Email)
		return nil

	case <-w.shutdownCh:
		idleCmd.Close()
		return nil
	case <-w.syncCh:
		idleCmd.Close()
		log.Printf("🔄 收到手动同步请求: %s", w.account.Email)
		return nil
	}
}

func (w *AccountWorker) idleRefreshInterval() time.Duration {
	// 可靠 IDLE 服务器由推送驱动；每分钟做一次安全校验即可。
	// 不能复用 5 秒轮询配置，否则会频繁退出 IDLE、重复登录。
	return time.Minute
}

// newIMAPClientWithHandler 创建带有 UnilateralDataHandler 的 IMAP 客户端
// 用于 IDLE 模式下接收服务器的实时推送
func (w *AccountWorker) newIMAPClientWithHandler(mailboxCh chan struct{}) (*IMAPClient, error) {
	host := w.account.ImapHost
	port := w.account.Port
	addr := net.JoinHostPort(host, strconv.Itoa(port))

	// TLS 配置（复用 client.go 中的配置逻辑）
	tlsConfig := &tls.Config{
		ServerName: host,
		MinVersion: tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_AES_128_GCM_SHA256,
			tls.TLS_AES_256_GCM_SHA384,
			tls.TLS_CHACHA20_POLY1305_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
			tls.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
			tls.TLS_RSA_WITH_AES_128_CBC_SHA,
			tls.TLS_RSA_WITH_AES_256_CBC_SHA,
		},
	}

	var imapClient *imapclient.Client
	var err error

	// 直连方式创建客户端（与 NewIMAPClient 保持一致）
	options := &imapclient.Options{
		TLSConfig: tlsConfig,
		UnilateralDataHandler: &imapclient.UnilateralDataHandler{
			// ⭐ 关键: 监听 Mailbox 状态变化 (EXISTS/EXPUNGE 等)
			Mailbox: func(data *imapclient.UnilateralDataMailbox) {
				if data.NumMessages != nil {
					// 收件箱邮件数量变化 → 新邮件到达或删除
					// 向 channel 发送信号（非阻塞，防止重复触发）
					select {
					case mailboxCh <- struct{}{}:
						log.Printf("📥 [%s] 检测到邮箱状态变更 (当前 %d 封)",
							w.account.Email, *data.NumMessages)
					default:
						// 已有待处理的通知，忽略
					}
				}
			},
			// 可选: 监听新邮件的详细数据
			Fetch: func(msg *imapclient.FetchMessageData) {
				// 通常 EXISTS 之后会跟随 FETCH 数据
				// 这里可以进一步处理邮件详情
				log.Printf("📧 [%s] 收到 FETCH 推送 (seq=%d)",
					w.account.Email, msg.SeqNum)
			},
		},
	}
	var conn net.Conn
	imapClient, conn, err = dialIMAPTLS(w.account, addr, tlsConfig, options)

	if err != nil {
		return nil, fmt.Errorf("连接 %s 失败: %w", addr, err)
	}

	return &IMAPClient{
		Client:  imapClient,
		Account: w.account,
		config:  w.config,
		conn:    conn,
	}, nil
}

// Stop 停止此 Worker
func (w *AccountWorker) Stop() {
	w.stopOnce.Do(func() { close(w.stopCh) })
}

func (w *AccountWorker) TriggerSync() {
	select {
	case w.syncCh <- struct{}{}:
	default:
	}
}

// updateAccountStatus 更新账号状态到数据库
func (w *AccountWorker) updateAccountStatus(status, errMsg string) {
	w.db.Model(&models.MailAccount{}).Where("id = ?", w.account.ID).
		Updates(map[string]interface{}{
			"status":    status,
			"error_msg": errMsg,
		})
	if status == "error" {
		log.Printf("❌ 同步错误 (%s): %s", w.account.Email, errMsg)
	}
}

// isIdleClosed 判断错误是否为 IDLE 正常结束
func isIdleClosed(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return contains(msg, "idle terminated") ||
		contains(msg, "connection closed") ||
		contains(msg, "EOF")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsStr(s, substr))
}

func containsStr(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// stripHTML 移除 HTML 标签，返回纯文本（用于 webhook preview fallback）
// 会完整移除 <style> 和 <script> 标签及其内部内容，避免 CSS/JS 代码泄漏到预览文本中
func stripHTML(html string) string {
	s := html

	// 1. 先移除 <style>...</style> 和 <script>...</script> 块（大小写不敏感）
	for _, tag := range []string{"style", "script"} {
		for {
			lower := strings.ToLower(s)
			startTag := "<" + tag
			endTag := "</" + tag + ">"

			startIdx := strings.Index(lower, startTag)
			if startIdx == -1 {
				break
			}
			// 找到起始标签的 '>' 位置
			startClose := strings.Index(s[startIdx:], ">")
			if startClose == -1 {
				break
			}
			contentStart := startIdx + startClose + 1
			endIdx := strings.Index(strings.ToLower(s[contentStart:]), endTag)
			if endIdx == -1 {
				// 没有闭合标签，只移除到末尾
				s = s[:startIdx]
				break
			}
			s = s[:startIdx] + s[contentStart+endIdx+len(endTag):]
		}
	}

	// 2. 移除剩余 HTML 标签
	var result strings.Builder
	inTag := false
	for _, r := range s {
		if r == '<' {
			inTag = true
			continue
		}
		if r == '>' {
			inTag = false
			continue
		}
		if !inTag {
			result.WriteRune(r)
		}
	}

	// 3. 清理多余空白：将连续空白替换为单个空格
	raw := result.String()
	var cleaned strings.Builder
	prevSpace := false
	for _, r := range raw {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			if !prevSpace {
				cleaned.WriteRune(' ')
				prevSpace = true
			}
		} else {
			cleaned.WriteRune(r)
			prevSpace = false
		}
	}
	return strings.TrimSpace(cleaned.String())
}
