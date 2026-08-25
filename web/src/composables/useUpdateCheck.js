/**
 * 版本更新检测 composable
 *
 * 通过请求 EdgeOne Pages 托管的 version.json 检测是否有新版本。
 * 支持本地缓存（默认 1 小时），避免频繁请求。
 *
 * 用法:
 *   const { hasUpdate, latestVersion, currentVersion, checkUpdate } = useUpdateCheck()
 *   await checkUpdate()          // 检查一次
 *   await checkUpdate(true)      // 强制检查（忽略缓存）
 */
import { ref } from 'vue'

const CACHE_KEY = 'cosmomail-update-check'
const CACHE_DURATION = 60 * 60 * 1000 // 1 小时缓存

// 全局单例状态（多个组件共享同一份检查结果）
const latestVersion = ref('')
const hasUpdate = ref(false)
const changelog = ref({})
const downloadUrl = ref('')
const loading = ref(false)
let lastCheckedAt = 0

/** 解析版本号字符串为可比较的数字数组 */
function parseVer(v) {
  if (!v) return [0, 0, 0]
  return (v.replace(/^v/i, '')).split('.').map(n => parseInt(n, 10) || 0)
}

/**
 * 比较 two versions.
 * Returns positive if b > a, negative if b < a, zero if equal.
 */
function compareVersions(a, b) {
  const pa = parseVer(a), pb = parseVer(b)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pb[i] || 0) - (pa[i] || 0)
    if (diff !== 0) return diff
  }
  return 0
}

export function useUpdateCheck() {
  /** 读取缓存 */
  function getCached() {
    try {
      const raw = localStorage.getItem(CACHE_KEY)
      if (!raw) return null
      const cached = JSON.parse(raw)
      if (Date.now() - cached.timestamp < CACHE_DURATION) {
        return cached
      }
    } catch {
      // ignore
    }
    return null
  }

  /** 写入缓存 */
  function setCache(data) {
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify({ ...data, timestamp: Date.now() }))
    } catch {
      // ignore
    }
  }

  /**
   * 执行版本检测
   * @param {boolean} force - 是否忽略缓存强制请求远程
   */
  async function checkUpdate(force = false) {
    // 非强制模式且缓存有效，直接使用缓存结果
    if (!force && Date.now() - lastCheckedAt < CACHE_DURATION) {
      // 已经有检查结果了，不需要重复计算
      return { hasUpdate: hasUpdate.value, latestVersion: latestVersion.value }
    }

    // 尝试读取缓存
    if (!force) {
      const cached = getCached()
      if (cached) {
        latestVersion.value = cached.latestVersion
        changelog.value = cached.changelog || {}
        downloadUrl.value = cached.downloadUrl || ''
        hasUpdate.value = compareVersions(__APP_VERSION__, cached.latestVersion) < 0
        lastCheckedAt = Date.now()
        return { hasUpdate: hasUpdate.value, latestVersion: latestVersion.value }
      }
    }

    // 远程请求
    const url = __UPDATE_CHECK_URL__ || ''
    if (!url) {
      console.warn('[UpdateCheck] 未配置 UPDATE_CHECK_URL，跳过版本检查')
      return { hasUpdate: false, latestVersion: '' }
    }

    loading.value = true
    try {
      const resp = await fetch(url, {
        cache: force ? 'no-cache' : 'default',
        signal: AbortSignal.timeout(8000),
      })
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)

      const data = await resp.json()
      const remote = data.latest?.replace(/^v/i, '') || ''

      if (!remote) throw new Error('无效的版本数据')

      latestVersion.value = data.latest
      changelog.value = data.changelog || {}
      downloadUrl.value = data.downloadUrl || data.githubUrl || ''

      // 缓存结果
      setCache({
        latestVersion: data.latest,
        changelog: data.changelog,
        downloadUrl: data.downloadUrl || '',
      })

      // 对比版本号
      hasUpdate.value = compareVersions(__APP_VERSION__, remote) < 0
      lastCheckedAt = Date.now()

      return { hasUpdate: hasUpdate.value, latestVersion: data.latest }
    } catch (e) {
      console.warn('[UpdateCheck] 检查失败:', e.message)
      return { hasUpdate: false, latestVersion: '', error: e.message }
    } finally {
      loading.value = false
    }
  }

  /** 重置更新提示状态（用户点击"忽略"后调用） */
  function dismiss() {
    hasUpdate.value = false
  }

  return {
    latestVersion,
    currentVersion: __APP_VERSION__,
    hasUpdate,
    changelog,
    downloadUrl,
    loading,
    checkUpdate,
    dismiss,
  }
}
