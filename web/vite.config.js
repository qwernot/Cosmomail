import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { VitePWA } from 'vite-plugin-pwa'
import { readFileSync } from 'fs'
import { resolve } from 'path'

// 从 package.json 读取版本号
const pkg = JSON.parse(readFileSync('./package.json', 'utf-8'))

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version || '0.0.0'),
    __UPDATE_CHECK_URL__: JSON.stringify(
      process.env.UPDATE_CHECK_URL
      || 'https://raw.githubusercontent.com/qwernot/Cosmomail/main/version.json'
    ),
  },
  plugins: [
    vue(),
    VitePWA({
      strategies: 'injectManifest',       // 显式启用 injectManifest 模式
      srcDir: 'src',                      // SW 源文件在 src 目录（默认是 public）
      registerType: 'prompt',
      includeAssets: ['icons/*.png'],
      // 自定义 Service Worker 源文件（含 push 事件处理）
      swSrc: resolve(__dirname, 'src/sw.js'),
      manifest: {
        name: 'Cosmo Mail',
        short_name: 'Cosmo Mail',
        description: '多邮箱 IMAP 代收客户端',
        theme_color: '#4F6EF7',
        background_color: '#ffffff',
        display: 'standalone',
        orientation: 'any',
        scope: '/',
        start_url: '/',
        icons: [
          {
            src: '/icons/icon-192x192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512x512.png',
            sizes: '512x512',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable'
          }
        ]
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
      }
    })
  ],
  server: {
    port: 5173,
    allowedHosts: true,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true
      }
    }
  },
  resolve: {
    alias: {
      '@': '/src'
    }
  },
  build: {
    outDir: '../server/dist',
    emptyOutDir: true
  }
})
