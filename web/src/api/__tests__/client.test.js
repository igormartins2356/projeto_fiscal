import axios from 'axios'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api, loadSession, onSessionLost, saveSession } from '../client'

// Adapter falso por instância (axios aceita `defaults.adapter`): evita rede e deixa cada teste decidir a resposta.
// O interceptor de erro precisa de uma rejeição com `config` e `response`, que é o contrato do adapter real.
function useAdapter(handler) {
  const calls = []
  api.defaults.adapter = (config) => {
    calls.push(config)
    const res = handler(config, calls.length)
    if (res.status >= 400) {
      const e = new Error(`status ${res.status}`)
      e.config = config
      e.response = { status: res.status, data: {} }
      return Promise.reject(e)
    }
    return Promise.resolve({ status: res.status, statusText: 'ok', data: res.data ?? {}, headers: {}, config })
  }
  return calls
}

describe('interceptor de refresh do client', () => {
  beforeEach(() => {
    localStorage.clear()
    onSessionLost.handler = vi.fn()
    saveSession({ access_token: 'velho', refresh_token: 'r1' })
  })
  afterEach(() => {
    delete api.defaults.adapter
    vi.restoreAllMocks()
  })

  it('401 → renova a sessão e repete a requisição com o token novo', async () => {
    const post = vi.spyOn(axios, 'post').mockResolvedValue({ data: { access_token: 'novo', refresh_token: 'r2' } })
    const calls = useAdapter((_c, n) => (n === 1 ? { status: 401 } : { status: 200, data: { ok: true } }))

    const res = await api.get('/clients')

    expect(res.data).toEqual({ ok: true })
    expect(post).toHaveBeenCalledWith(expect.stringContaining('/auth/refresh'), { refresh_token: 'r1' })
    expect(calls[1].headers.Authorization).toBe('Bearer novo')
    expect(loadSession()).toEqual({ access_token: 'novo', refresh_token: 'r2' })
    expect(onSessionLost.handler).not.toHaveBeenCalled()
  })

  it('duas requisições concorrentes com 401 renovam a sessão uma única vez', async () => {
    const post = vi.spyOn(axios, 'post').mockResolvedValue({ data: { access_token: 'novo', refresh_token: 'r2' } })
    useAdapter((config) => (config._retried ? { status: 200, data: { ok: true } } : { status: 401 }))

    await Promise.all([api.get('/clients'), api.get('/audit_runs')])

    expect(post).toHaveBeenCalledTimes(1)
  })

  it('401 sem refresh_token limpa a sessão em vez de deixar o app "autenticado" com tudo falhando', async () => {
    saveSession({ access_token: 'velho' })
    const post = vi.spyOn(axios, 'post')
    useAdapter(() => ({ status: 401 }))

    await expect(api.get('/clients')).rejects.toThrow()

    expect(post).not.toHaveBeenCalled()
    expect(loadSession()).toBe(null)
    expect(onSessionLost.handler).toHaveBeenCalledTimes(1)
  })

  it('401 no login não tenta refresh (senha errada não é sessão expirada)', async () => {
    const post = vi.spyOn(axios, 'post')
    const calls = useAdapter(() => ({ status: 401 }))

    await expect(api.post('/auth/login', {})).rejects.toThrow()

    expect(post).not.toHaveBeenCalled()
    expect(calls).toHaveLength(1)
    expect(loadSession()).toEqual({ access_token: 'velho', refresh_token: 'r1' })
  })

  it('refresh que falha limpa a sessão e propaga o erro', async () => {
    vi.spyOn(axios, 'post').mockRejectedValue(new Error('refresh_token expirado'))
    useAdapter(() => ({ status: 401 }))

    await expect(api.get('/clients')).rejects.toThrow('refresh_token expirado')

    expect(loadSession()).toBe(null)
    expect(onSessionLost.handler).toHaveBeenCalledTimes(1)
  })
})
