import { defineStore } from 'pinia'
import { auth, loadSession, saveSession, setClientId, onSessionLost } from '../api/client'

// QueryClient do Vue Query, injetado em bindSessionLost: fora do state para não virar reativo.
let queryClient = null

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
    // A troca de senha invalida todo token anterior, inclusive o desta aba: adotamos o par novo que a
    // API devolve, senão quem trocou a própria senha cairia na tela de login logo depois.
    async changePassword(current_password, password) {
      const res = await auth.changePassword(current_password, password)
      if (res?.access_token) saveSession({ ...loadSession(), access_token: res.access_token, refresh_token: res.refresh_token })
    },
    async refreshUser() { try { this.user = await auth.me(); saveSession({ ...loadSession(), user: this.user }) } catch {} },
    async logout() {
      const s = loadSession()
      try { if (s?.refresh_token) await auth.logout(s.refresh_token) } catch {}
      this.clear()
    },
    // Limpa também o cache do Vue Query: sem isto o próximo login (outro usuário/firma, mesma aba) recebe
    // ['clients'] da firma anterior e restore() fixa um clientId estranho à firma → 422 em tudo.
    clear() { saveSession(null); this.user = null; this.select(null); queryClient?.clear() },
    select(id) {
      this.clientId = id
      setClientId(id)
      try { id ? localStorage.setItem('clientId', String(id)) : localStorage.removeItem('clientId') } catch {}
    },
    // Chamado sempre que a lista de clientes muda: mantém o atual se ainda existir, senão o salvo, senão o primeiro.
    restore(clients) {
      let saved = null
      try { saved = Number(localStorage.getItem('clientId')) } catch {}
      const current = clients.find(c => c.id === this.clientId)?.id
      this.select(current ?? clients.find(c => c.id === saved)?.id ?? clients[0]?.id ?? null)
    },
    bindSessionLost(router, qc = null) {
      queryClient = qc
      onSessionLost.handler = () => { this.clear(); router.push({ path: '/login', query: { expired: '1' } }) }
    },
  },
})
