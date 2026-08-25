<!--
  SPDX-License-Identifier: AGPL-3.0-or-later
  Copyright (C) 2026 magiccode (魔法代码)
  Modifications Copyright (C) 2026 Cosmo Mail contributors
-->
<template>
  <div class="auth-page">
    <div class="aurora aurora-pink"></div>
    <div class="aurora aurora-mint"></div>
    <div class="star-field"></div>

    <button class="theme-toggle" type="button" @click="appStore.toggleTheme()" :title="themeTitle" aria-label="切换主题">
      <svg v-if="appStore.themeMode === 'system'" viewBox="0 0 24 24" aria-hidden="true">
        <rect x="3" y="5" width="18" height="13" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/>
        <path d="M8 21h8M12 18v3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
      </svg>
      <svg v-else-if="appStore.themeMode === 'light'" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="4.5" fill="currentColor"/>
        <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
      </svg>
      <svg v-else viewBox="0 0 24 24" aria-hidden="true">
        <path d="M19.5 14.5A8 8 0 0 1 9.5 4.4a8 8 0 1 0 10 10.1Z" fill="currentColor"/>
      </svg>
    </button>

    <main class="auth-layout">
      <section class="brand-scene" aria-label="Cosmo Mail">
        <div class="brand-lockup">
          <div class="logo-orbit">
            <span class="orbit orbit-one"></span>
            <span class="orbit orbit-two"></span>
            <img src="/icons/icon-512x512.png" alt="" class="brand-logo" />
            <i class="satellite satellite-one"></i>
            <i class="satellite satellite-two"></i>
          </div>
          <p class="brand-kicker">COSMO MAIL</p>
          <h1>把所有邮箱，<br />收进同一片轨道。</h1>
          <p class="brand-copy">聚合多个邮箱账号，快速同步、集中阅读，让每一封重要邮件都准时抵达。</p>
          <div class="feature-row" aria-label="产品特点">
            <span><i></i> 增量同步</span>
            <span><i></i> 本地存储</span>
            <span><i></i> 实时提醒</span>
          </div>
        </div>
      </section>

      <section class="auth-card" :class="{ 'register-card': isRegister }">
        <div class="mobile-brand">
          <img src="/icons/icon-128x128.png" alt="" />
          <span>Cosmo Mail</span>
        </div>

        <transition name="panel-fade" mode="out-in">
          <div v-if="!isRegister" key="login" class="form-panel">
            <header class="form-header">
              <p class="form-eyebrow">WELCOME BACK</p>
              <h2>登录你的收件空间</h2>
              <p>使用管理员账号继续进入 Cosmo Mail</p>
            </header>

            <form class="auth-form" autocomplete="on" @submit.prevent="handleSubmit">
              <label class="field" :class="{ focused: focused === 'username', invalid: errors.username }">
                <span class="field-caption">用户名</span>
                <span class="input-wrap">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <circle cx="12" cy="8" r="4" fill="none" stroke="currentColor" stroke-width="1.7"/>
                    <path d="M4.5 21c.5-4.2 3-6.5 7.5-6.5s7 2.3 7.5 6.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                  </svg>
                  <input
                    ref="usernameInput"
                    v-model="form.username"
                    type="text"
                    placeholder="请输入用户名"
                    autocomplete="username"
                    @focus="focused = 'username'"
                    @blur="focused = ''"
                  />
                </span>
                <small v-if="errors.username">{{ errors.username }}</small>
              </label>

              <label class="field" :class="{ focused: focused === 'password', invalid: errors.password }">
                <span class="field-caption">密码</span>
                <span class="input-wrap">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <rect x="4" y="10" width="16" height="11" rx="3" fill="none" stroke="currentColor" stroke-width="1.7"/>
                    <path d="M8 10V7a4 4 0 0 1 8 0v3" fill="none" stroke="currentColor" stroke-width="1.7"/>
                  </svg>
                  <input
                    ref="passwordInput"
                    v-model="form.password"
                    :type="showPassword ? 'text' : 'password'"
                    placeholder="请输入密码"
                    autocomplete="current-password"
                    @focus="focused = 'password'"
                    @blur="focused = ''"
                  />
                  <button class="reveal-button" type="button" tabindex="-1" @click="showPassword = !showPassword">
                    {{ showPassword ? '隐藏' : '显示' }}
                  </button>
                </span>
                <small v-if="errors.password">{{ errors.password }}</small>
              </label>

              <div v-if="errorMsg" class="error-message" role="alert">{{ errorMsg }}</div>

              <button class="submit-button" type="submit" :disabled="submitting">
                <span v-if="submitting" class="spinner"></span>
                <template v-else>
                  进入邮箱
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M5 12h13M14 7l5 5-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                </template>
              </button>

              <button v-if="canRegister" class="mode-button" type="button" @click="switchToRegister">
                首次使用？创建管理员账号
              </button>
            </form>
          </div>

          <div v-else key="register" class="form-panel">
            <header class="form-header">
              <p class="form-eyebrow">FIRST LAUNCH</p>
              <h2>创建管理员账号</h2>
              <p>完成初始化后，就可以添加你的邮箱</p>
            </header>

            <form class="auth-form" autocomplete="on" @submit.prevent="handleRegister">
              <label class="field" :class="{ focused: focused === 'username', invalid: errors.username }">
                <span class="field-caption">管理员用户名</span>
                <span class="input-wrap">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <circle cx="12" cy="8" r="4" fill="none" stroke="currentColor" stroke-width="1.7"/>
                    <path d="M4.5 21c.5-4.2 3-6.5 7.5-6.5s7 2.3 7.5 6.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                  </svg>
                  <input
                    v-model="regForm.username"
                    type="text"
                    placeholder="3–32 个字符"
                    autocomplete="username"
                    @focus="focused = 'username'"
                    @blur="focused = ''"
                  />
                </span>
                <small v-if="errors.username">{{ errors.username }}</small>
              </label>

              <label class="field" :class="{ focused: focused === 'password', invalid: errors.password }">
                <span class="field-caption">设置密码</span>
                <span class="input-wrap">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <rect x="4" y="10" width="16" height="11" rx="3" fill="none" stroke="currentColor" stroke-width="1.7"/>
                    <path d="M8 10V7a4 4 0 0 1 8 0v3" fill="none" stroke="currentColor" stroke-width="1.7"/>
                  </svg>
                  <input
                    v-model="regForm.password"
                    :type="showRegPassword ? 'text' : 'password'"
                    placeholder="至少 6 位"
                    autocomplete="new-password"
                    @focus="focused = 'password'"
                    @blur="focused = ''"
                  />
                  <button class="reveal-button" type="button" tabindex="-1" @click="showRegPassword = !showRegPassword">
                    {{ showRegPassword ? '隐藏' : '显示' }}
                  </button>
                </span>
                <small v-if="errors.password">{{ errors.password }}</small>
              </label>

              <label class="field" :class="{ focused: focused === 'confirmPwd', invalid: errors.confirmPwd }">
                <span class="field-caption">确认密码</span>
                <span class="input-wrap">
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="m5 12 4 4L19 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                  <input
                    v-model="regForm.confirmPassword"
                    :type="showRegPassword ? 'text' : 'password'"
                    placeholder="再次输入密码"
                    autocomplete="new-password"
                    @focus="focused = 'confirmPwd'"
                    @blur="focused = ''"
                  />
                </span>
                <small v-if="errors.confirmPwd">{{ errors.confirmPwd }}</small>
              </label>

              <div v-if="errorMsg" class="error-message" role="alert">{{ errorMsg }}</div>

              <button class="submit-button" type="submit" :disabled="submitting">
                <span v-if="submitting" class="spinner"></span>
                <template v-else>创建并进入</template>
              </button>
              <button class="mode-button" type="button" @click="isRegister = false; clearErrors()">返回登录</button>
            </form>
          </div>
        </transition>
      </section>
    </main>
  </div>
</template>

<script setup>
defineOptions({ name: 'Login' })
import { ref, reactive, computed, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'
import { useAppStore } from '@/stores/appStore'

const router = useRouter()
const authStore = useAuthStore()
const appStore = useAppStore()

const themeTitle = computed(() => {
  const titles = { system: '跟随系统', light: '浅色模式', dark: '深色模式' }
  return titles[appStore.themeMode] || '切换主题'
})

const DEV_DEFAULT_USERNAME = import.meta.env.DEV ? 'admin' : ''
const DEV_DEFAULT_PASSWORD = import.meta.env.DEV ? 'admin123' : ''

const form = reactive({ username: DEV_DEFAULT_USERNAME, password: DEV_DEFAULT_PASSWORD })
const regForm = reactive({ username: '', password: '', confirmPassword: '' })
const errors = reactive({ username: '', password: '', confirmPwd: '' })
const errorMsg = ref('')
const submitting = ref(false)
const showPassword = ref(false)
const showRegPassword = ref(false)
const focused = ref('')
const usernameInput = ref(null)
const passwordInput = ref(null)

const isRegister = ref(authStore.setupRequired)
const canRegister = computed(() => authStore.setupRequired)

function switchToRegister() {
  isRegister.value = true
  clearErrors()
}

function clearErrors() {
  errors.username = ''
  errors.password = ''
  errors.confirmPwd = ''
  errorMsg.value = ''
}

async function handleSubmit() {
  clearErrors()
  if (!form.username.trim()) { errors.username = '请输入用户名'; return }
  if (!form.password) { errors.password = '请输入密码'; return }

  submitting.value = true
  try {
    await authStore.doLogin(form)
    router.push('/')
  } catch (e) {
    errorMsg.value = e.message || '登录失败，请重试'
  } finally {
    submitting.value = false
  }
}

async function handleRegister() {
  clearErrors()
  let hasError = false

  if (!regForm.username.trim()) { errors.username = '请输入用户名'; hasError = true }
  else if (regForm.username.length < 3) { errors.username = '用户名至少 3 位'; hasError = true }
  else if (regForm.username.length > 32) { errors.username = '用户名不超过 32 位'; hasError = true }

  if (!regForm.password) { errors.password = '请输入密码'; hasError = true }
  else if (regForm.password.length < 6) { errors.password = '密码至少 6 位'; hasError = true }

  if (!regForm.confirmPassword) { errors.confirmPwd = '请确认密码'; hasError = true }
  else if (regForm.password !== regForm.confirmPassword) { errors.confirmPwd = '两次密码不一致'; hasError = true }

  if (hasError) return

  submitting.value = true
  try {
    await authStore.doRegister(regForm)
    router.push('/')
  } catch (e) {
    errorMsg.value = e.message || '注册失败，请重试'
  } finally {
    submitting.value = false
  }
}

onMounted(async () => {
  if (!authStore.initialized) await authStore.init()
  isRegister.value = authStore.setupRequired

  if (import.meta.env.DEV && form.username) {
    await nextTick()
    passwordInput.value?.focus()
  }
})
</script>

<style scoped>
.auth-page {
  --cosmo-ink: #21152d;
  --cosmo-muted: #786d82;
  --cosmo-card: rgba(255, 252, 250, 0.92);
  --cosmo-line: rgba(62, 32, 78, 0.12);
  --cosmo-pink: #f38bc1;
  --cosmo-purple: #6f3187;
  --cosmo-mint: #dfffc6;
  position: relative;
  min-height: 100vh;
  display: grid;
  place-items: center;
  overflow: hidden;
  padding: 44px;
  background: #f7f0f6;
  color: var(--cosmo-ink);
  isolation: isolate;
}

[data-theme="dark"] .auth-page {
  --cosmo-ink: #fff8fd;
  --cosmo-muted: #b8aabd;
  --cosmo-card: rgba(31, 20, 39, 0.9);
  --cosmo-line: rgba(255, 255, 255, 0.1);
  background: #160e1e;
}

.aurora {
  position: absolute;
  z-index: -3;
  width: 62vw;
  height: 62vw;
  border-radius: 50%;
  filter: blur(10px);
  opacity: 0.62;
}
.aurora-pink {
  top: -36vw;
  right: -18vw;
  background: radial-gradient(circle, rgba(243, 139, 193, 0.85), rgba(154, 91, 176, 0.12) 58%, transparent 72%);
}
.aurora-mint {
  bottom: -40vw;
  left: -22vw;
  background: radial-gradient(circle, rgba(223, 255, 198, 0.95), rgba(132, 200, 189, 0.1) 62%, transparent 74%);
}
.star-field {
  position: absolute;
  z-index: -2;
  inset: 0;
  opacity: 0.48;
  background-image:
    radial-gradient(circle at 14% 21%, currentColor 0 1px, transparent 1.5px),
    radial-gradient(circle at 72% 16%, currentColor 0 1px, transparent 1.5px),
    radial-gradient(circle at 88% 76%, currentColor 0 1px, transparent 1.5px),
    radial-gradient(circle at 32% 84%, currentColor 0 1px, transparent 1.5px);
  background-size: 190px 190px, 270px 270px, 230px 230px, 310px 310px;
  color: rgba(111, 49, 135, 0.25);
}

.theme-toggle {
  position: fixed;
  z-index: 10;
  top: 22px;
  right: 24px;
  width: 42px;
  height: 42px;
  display: grid;
  place-items: center;
  border: 1px solid var(--cosmo-line);
  border-radius: 50%;
  background: var(--cosmo-card);
  color: var(--cosmo-purple);
  box-shadow: 0 10px 30px rgba(70, 32, 86, 0.08);
  cursor: pointer;
  backdrop-filter: blur(18px);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.theme-toggle:hover { transform: translateY(-2px) rotate(8deg); box-shadow: 0 14px 34px rgba(70, 32, 86, 0.14); }
.theme-toggle svg { width: 20px; height: 20px; }

.auth-layout {
  width: min(1080px, 100%);
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(380px, 0.8fr);
  align-items: center;
  gap: clamp(48px, 8vw, 118px);
}

.brand-scene { padding: 20px 0 20px 18px; }
.brand-lockup { max-width: 570px; }
.logo-orbit {
  position: relative;
  width: 142px;
  height: 142px;
  display: grid;
  place-items: center;
  margin-bottom: 26px;
}
.brand-logo {
  position: relative;
  z-index: 2;
  width: 104px;
  height: 104px;
  object-fit: contain;
  filter: drop-shadow(0 18px 22px rgba(70, 32, 86, 0.2));
  animation: logo-float 5s ease-in-out infinite;
}
.orbit {
  position: absolute;
  inset: 6px;
  border: 1px solid rgba(111, 49, 135, 0.28);
  border-radius: 50%;
  transform: rotate(-18deg) scaleY(0.5);
}
.orbit-two { inset: -9px; transform: rotate(28deg) scaleY(0.62); opacity: 0.45; }
.satellite {
  position: absolute;
  z-index: 3;
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: var(--cosmo-purple);
  box-shadow: 0 0 0 5px rgba(111, 49, 135, 0.1);
}
.satellite-one { top: 27px; right: 12px; }
.satellite-two { bottom: 18px; left: 18px; background: var(--cosmo-pink); }
@keyframes logo-float { 50% { transform: translateY(-7px) rotate(2deg); } }

.brand-kicker,
.form-eyebrow {
  margin: 0 0 12px;
  color: var(--cosmo-purple);
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.24em;
}
.brand-scene h1 {
  margin: 0;
  font-size: clamp(42px, 5vw, 68px);
  line-height: 1.08;
  letter-spacing: -0.055em;
  font-weight: 850;
}
.brand-copy {
  max-width: 510px;
  margin: 24px 0 28px;
  color: var(--cosmo-muted);
  font-size: 16px;
  line-height: 1.85;
}
.feature-row { display: flex; flex-wrap: wrap; gap: 10px; }
.feature-row span {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border: 1px solid var(--cosmo-line);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.38);
  color: var(--cosmo-muted);
  font-size: 12px;
  font-weight: 650;
}
[data-theme="dark"] .feature-row span { background: rgba(255, 255, 255, 0.04); }
.feature-row i { width: 6px; height: 6px; border-radius: 50%; background: var(--cosmo-pink); }
.feature-row span:nth-child(2) i { background: #86c7bc; }
.feature-row span:nth-child(3) i { background: var(--cosmo-purple); }

.auth-card {
  position: relative;
  padding: 42px;
  border: 1px solid var(--cosmo-line);
  border-radius: 30px;
  background: var(--cosmo-card);
  box-shadow: 0 32px 90px rgba(67, 35, 77, 0.16), inset 0 1px 0 rgba(255, 255, 255, 0.45);
  backdrop-filter: blur(24px);
  transition: min-height 0.25s ease;
}
.auth-card::before {
  content: '';
  position: absolute;
  inset: 10px;
  border: 1px solid rgba(255, 255, 255, 0.35);
  border-radius: 22px;
  pointer-events: none;
}
.mobile-brand { display: none; }
.form-panel { position: relative; z-index: 1; }
.form-header { margin-bottom: 30px; }
.form-header h2 { margin: 0 0 9px; font-size: 28px; letter-spacing: -0.035em; }
.form-header > p:last-child { margin: 0; color: var(--cosmo-muted); font-size: 13px; line-height: 1.6; }
.form-eyebrow { margin-bottom: 10px; font-size: 10px; }
.auth-form { display: grid; gap: 19px; }
.field { display: grid; gap: 8px; }
.field-caption { color: var(--cosmo-muted); font-size: 12px; font-weight: 700; }
.input-wrap {
  height: 50px;
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 0 15px;
  border: 1px solid var(--cosmo-line);
  border-radius: 15px;
  background: rgba(255, 255, 255, 0.48);
  transition: border-color 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease;
}
[data-theme="dark"] .input-wrap { background: rgba(255, 255, 255, 0.035); }
.field.focused .input-wrap {
  border-color: rgba(111, 49, 135, 0.58);
  box-shadow: 0 0 0 4px rgba(243, 139, 193, 0.13);
  transform: translateY(-1px);
}
.field.invalid .input-wrap { border-color: #dc5d78; box-shadow: 0 0 0 4px rgba(220, 93, 120, 0.1); }
.input-wrap > svg { flex: 0 0 auto; width: 19px; height: 19px; color: var(--cosmo-purple); }
.input-wrap input {
  min-width: 0;
  flex: 1;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--cosmo-ink);
  font: inherit;
  font-size: 14px;
}
.input-wrap input::placeholder { color: color-mix(in srgb, var(--cosmo-muted) 68%, transparent); }
.reveal-button {
  border: 0;
  padding: 5px;
  background: transparent;
  color: var(--cosmo-muted);
  font-size: 11px;
  cursor: pointer;
}
.field small { color: #d54567; font-size: 11px; }
.error-message {
  padding: 11px 13px;
  border: 1px solid rgba(213, 69, 103, 0.2);
  border-radius: 12px;
  background: rgba(213, 69, 103, 0.08);
  color: #d54567;
  font-size: 12px;
}
.submit-button {
  height: 52px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  border: 0;
  border-radius: 15px;
  background: linear-gradient(120deg, #6f3187, #a9569b 55%, #ed83b9);
  color: #fff;
  box-shadow: 0 15px 30px rgba(111, 49, 135, 0.25);
  font: inherit;
  font-size: 14px;
  font-weight: 750;
  cursor: pointer;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.submit-button:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 19px 34px rgba(111, 49, 135, 0.31); }
.submit-button:disabled { opacity: 0.62; cursor: wait; }
.submit-button svg { width: 18px; height: 18px; }
.mode-button {
  border: 0;
  padding: 2px;
  background: transparent;
  color: var(--cosmo-purple);
  font: inherit;
  font-size: 12px;
  font-weight: 650;
  cursor: pointer;
}
.spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
.panel-fade-enter-active, .panel-fade-leave-active { transition: opacity 0.18s ease, transform 0.18s ease; }
.panel-fade-enter-from { opacity: 0; transform: translateY(10px); }
.panel-fade-leave-to { opacity: 0; transform: translateY(-8px); }

@media (max-width: 860px) {
  .auth-page { padding: 70px 22px 32px; overflow: auto; }
  .auth-layout { width: min(460px, 100%); grid-template-columns: 1fr; gap: 22px; }
  .brand-scene { display: none; }
  .mobile-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 28px;
    color: var(--cosmo-ink);
    font-size: 17px;
    font-weight: 800;
  }
  .mobile-brand img { width: 46px; height: 46px; object-fit: contain; filter: drop-shadow(0 8px 10px rgba(70, 32, 86, 0.15)); }
}

@media (max-width: 480px) {
  .auth-page { padding: 66px 12px 18px; }
  .auth-card { padding: 30px 24px; border-radius: 24px; }
  .auth-card::before { border-radius: 17px; }
  .form-header h2 { font-size: 24px; }
  .theme-toggle { top: 14px; right: 14px; }
}

@media (prefers-reduced-motion: reduce) {
  .brand-logo, .spinner { animation: none; }
  *, *::before, *::after { transition-duration: 0.01ms !important; }
}
</style>
