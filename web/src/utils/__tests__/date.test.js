// Fuso do escritório (UTC-3): é onde `toISOString()` e `new Date('aaaa-mm-dd')` erram o dia.
process.env.TZ = 'America/Sao_Paulo'
import { describe, expect, it } from 'vitest'
import { fmtDate, fmtDateTime, toIso, todayIso } from '../date'

describe('toIso', () => {
  it('usa os componentes locais da data', () => {
    expect(toIso(new Date(2026, 7, 1))).toBe('2026-08-01')
  })

  it('não vira o dia para o seguinte à noite (21h30 em BRT já é o dia seguinte em UTC)', () => {
    const noite = new Date(2026, 7, 1, 21, 30)
    expect(noite.toISOString().slice(0, 10)).toBe('2026-08-02') // o que o código antigo devolvia
    expect(toIso(noite)).toBe('2026-08-01')
  })

  it('preserva o último dia do mês calculado com new Date(ano, mes, 0)', () => {
    expect(toIso(new Date(2026, 8, 0))).toBe('2026-08-31')
  })
})

describe('todayIso', () => {
  it('devolve a data local de hoje', () => {
    const hoje = new Date()
    expect(todayIso()).toBe(`${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-${String(hoje.getDate()).padStart(2, '0')}`)
  })
})

describe('fmtDate', () => {
  it('exibe aaaa-mm-dd como dd/mm/aaaa sem deslocar o dia', () => {
    expect(new Date('2026-08-01').toLocaleDateString('pt-BR')).toBe('31/07/2026') // o que o código antigo exibia
    expect(fmtDate('2026-08-01')).toBe('01/08/2026')
  })

  it('aceita timestamp completo e trata ausência', () => {
    expect(fmtDate('2026-08-01T23:10:00-03:00')).toBe('01/08/2026')
    expect(fmtDate(null)).toBe('')
    expect(fmtDate('')).toBe('')
  })
})

describe('fmtDateTime', () => {
  it('formata data e hora em pt-BR', () => {
    expect(fmtDateTime('2026-08-01T14:05:00-03:00')).toBe(new Date('2026-08-01T14:05:00-03:00').toLocaleString('pt-BR'))
    expect(fmtDateTime(null)).toBe('')
  })
})
