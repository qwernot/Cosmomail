import { defineConfig } from 'vitepress'

/**
 * 通过环境变量 VITEPRESS_BASE 设置部署基础路径（二级目录）
 * 例如部署在 /cosmomail 下：VITEPRESS_BASE=/cosmomail npm run docs:build
 *
 * 规则：
 *   未设置或为空 → 默认 '/'（根路径部署）
 *   缺少前导 / → 自动补全（如 cosmomail → /cosmomail）
 *   尾部有多余 / → 自动去除（如 /cosmomail/ → /cosmomail）
 */
const rawBase = process.env.VITEPRESS_BASE || '/'
const normalizedBase = rawBase.trim().replace(/^([^/])/, '/$1')
const base = normalizedBase === '/' ? '/' : `${normalizedBase.replace(/\/+$/, '')}/`

export default defineConfig({
  title: 'Cosmo Mail',
  description: 'Cosmo Mail - 快速、私有的统一邮件管理平台',
  lang: 'zh-CN',
  base,
  cleanUrls: true,
  lastUpdated: true,
  vite: {
    server: {
      host: '0.0.0.0',
      port: 3000,
      allowedHosts: true
    }
  },

  // 仅忽略开发环境的本地链接，保留对真实死链的检测能力
  ignoreDeadLinks: [/localhost:\d+/, /\d+\.\d+\.\d+\.\d+/],

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: `${base}icon.png` }],
    ['meta', { name: 'theme-color', content: '#8b5cf6' }],
    ['meta', { property: 'og:title', content: 'Cosmo Mail' }],
    ['meta', { property: 'og:description', content: '快速、私有的多邮箱统一管理平台' }],
  ],

  themeConfig: {
    logo: `${base}icon.png`,
    siteTitle: 'Cosmo Mail',

    nav: [
      { text: '指南', link: '/guide/getting-started' },
      { text: 'API', link: '/api/overview' },
      { text: '下载', link: 'https://github.com/qwernot/Cosmomail/releases/latest' },
      {
        text: '更多',
        items: [
          { text: '开发指南', link: '/dev/overview' },
          { text: '配置参考', link: '/config/environment' },
          { text: 'GitHub', link: 'https://github.com/qwernot/Cosmomail' },
          { text: '更新日志', link: '/guide/changelog' },
        ],
      },
    ],

    sidebar: {
      '/guide/': [
        {
          text: '开始使用',
          items: [
            { text: '快速开始', link: '/guide/getting-started' },
            { text: '安装部署', link: '/guide/installation' },
            { text: '功能特性', link: '/guide/features' },
          ],
        },
        {
          text: '使用手册',
          items: [
            { text: '邮箱管理', link: '/guide/accounts' },
            { text: '邮件收发', link: '/guide/mails' },
            { text: 'Webhook 通知', link: '/guide/webhooks' },
            { text: 'PWA 客户端', link: '/guide/pwa' },
            { text: 'Outlook OAuth2 配置', link: '/guide/oauth2-microsoft' },
          ],
        },
        {
          text: '版本信息',
          items: [
            { text: '更新日志', link: '/guide/changelog' },
            { text: '已知问题', link: '/guide/known-issues' },
          ],
        },
      ],
      '/api/': [
        { text: 'API 概览', link: '/api/overview' },
        { text: '认证接口', link: '/api/auth' },
        { text: '邮箱管理', link: '/api/accounts' },
        { text: '邮件管理', link: '/api/mails' },
        { text: '草稿接口', link: '/api/drafts' },
        { text: '附件接口', link: '/api/attachments' },
        { text: 'SSE 实时事件', link: '/api/sse' },
        { text: '推送接口', link: '/api/push' },
        { text: 'Webhook 接口', link: '/api/webhooks' },
      ],
      '/dev/': [
        { text: '开发概览', link: '/dev/overview' },
        { text: '项目架构', link: '/dev/architecture' },
        { text: '后端开发', link: '/dev/backend' },
        { text: '前端开发', link: '/dev/frontend' },
        { text: '添加 IMAP 功能', link: '/dev/imap-extension' },
        { text: '主题定制', link: '/dev/theming' },
      ],
      '/config/': [
        { text: '环境变量', link: '/config/environment' },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/qwernot/Cosmomail' },
    ],

    editLink: {
      pattern: 'https://github.com/qwernot/Cosmomail/edit/main/docs/:path',
      text: '在 GitHub 上编辑此页',
    },

    footer: {
      message: '基于 AGPLv3 协议开源',
      copyright: 'Copyright © 2024-present Cosmo Mail Contributors',
    },

    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: '搜索文档', buttonAriaLabel: '搜索文档' },
          modal: { noResultsText: '无法找到相关结果', resetButtonTitle: '清除查询条件', footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' } },
        },
      },
    },

    outline: {
      label: '页面导航',
    },

    lastUpdated: {
      text: '最后更新于',
    },

    docFooter: {
      prev: '上一页',
      next: '下一页',
    },
  },
})
