import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useSession } from '../session'

const router = { push: vi.fn() }

describe('useSession', () => {
  beforeEach(() => {
    localStorage.clear()
    setActivePinia(createPinia())
  })

  it('limpa o cache do Vue Query ao sair (o próximo login não herda os clientes da firma anterior)', () => {
    const queryClient = { clear: vi.fn() }
    const s = useSession()
    s.bindSessionLost(router, queryClient)
    s.select(54)
    s.clear()
    expect(queryClient.clear).toHaveBeenCalledTimes(1)
    expect(s.clientId).toBe(null)
    expect(localStorage.getItem('clientId')).toBe(null)
  })

  it('select(null) remove o clientId salvo em vez de deixar o anterior', () => {
    const s = useSession()
    s.select(54)
    expect(localStorage.getItem('clientId')).toBe('54')
    s.select(null)
    expect(localStorage.getItem('clientId')).toBe(null)
  })

  it('restore mantém o cliente atual quando ele continua na lista', () => {
    const s = useSession()
    s.select(54)
    localStorage.setItem('clientId', '55') // outra aba salvou outro cliente
    s.restore([{ id: 54 }, { id: 55 }])
    expect(s.clientId).toBe(54)
  })

  it('restore troca de cliente quando o atual sai da lista (firma diferente)', () => {
    const s = useSession()
    s.select(54)
    s.restore([{ id: 77 }, { id: 78 }])
    expect(s.clientId).toBe(77)
  })
})
