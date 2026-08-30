import { defineStore } from 'pinia'
import { auth, loadSession, saveSession, setClientId, onSessionLost } from '../api/client'

export const useSession = defineStore('session', {
  state: () => ({ user: loadSession()?.user ?? null, clientId: null, mfaToken: null }),
  getters: {
    authenticated: (s) => !!s.user,
    isFirmAdmin: (s) => ['firm_admin', 'platform_admin'].includes(s.user?.role),
    isPlatformAdmin: (s) => s.user?.role === 'platform_admin',
  },
  actions: {
    async login(email, password) {
      const res = await auth.login(email, password)
      if (res.mfa_required) { this.mfaToken = res.mfa_token; return { mfa: true } }
      this.establish(res)
      return { mfa: false }
    },
    async mfa(code) {
      const res = await auth.mfa(this.mfaToken, code)
      this.mfaToken = null
      this.establish(res)
    },
    establish(res) { saveSession(res); this.user = res.user },
    async refreshUser() { try { this.user = await auth.me(); saveSession({ ...loadSession(), user: this.user }) } catch {} },
    async logout() {
      const s = loadSession()
      try { if (s?.refresh_token) await auth.logout(s.refresh_token) } catch {}
      this.clear()
    },
    clear() { saveSession(null); this.user = null; this.select(null) },
    select(id) {
      this.clientId = id
      setClientId(id)
      try { if (id) localStorage.setItem('clientId', String(id)) } catch {}
    },
    restore(clients) {
      let saved = null
      try { saved = Number(localStorage.getItem('clientId')) } catch {}
      this.select(clients.find(c => c.id === saved)?.id ?? clients[0]?.id ?? null)
    },
    bindSessionLost(router) { onSessionLost.handler = () => { this.clear(); router.push({ path: '/login', query: { expired: '1' } }) } },
  },
})
