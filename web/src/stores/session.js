import { defineStore } from 'pinia'
import { setClientId } from '../api/client'

export const useSession = defineStore('session', {
  state: () => ({ clientId: null }),
  actions: {
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
  },
})
