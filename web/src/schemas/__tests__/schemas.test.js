import { describe, expect, it } from 'vitest'
import { ruleOverrideSchema, rowOverrideSchema } from '../override'
import { userSchema } from '../user'
import { changePasswordSchema } from '../password'
import { referenceTableSchema, referenceVersionSchema } from '../referenceTable'
import { newRuleSchema } from '../rule'

const erro = (schema, value, path) => {
  const r = schema.safeParse(value)
  expect(r.success).toBe(false)
  return r.error.issues.find(i => i.path.join('.') === path)?.message
}

const overrideBase = { rule_code: 'ICMS.CSOSN.SALE_RETURN', source_type: 'client', source_id: 54, override_action: 'disable', patch: {}, effective_from: '2026-08-01', effective_until: null, justification: 'entendimento do escritório' }

describe('ruleOverrideSchema', () => {
  it('aceita a sobreposição completa', () => {
    expect(ruleOverrideSchema.safeParse(overrideBase).success).toBe(true)
  })

  it('exige o cliente quando o alvo é um cliente', () => {
    expect(erro(ruleOverrideSchema, { ...overrideBase, source_id: null }, 'source_id')).toBe('Selecione o cliente')
  })

  it('exige justificativa e código no formato PREFIXO.ASSUNTO.DETALHE', () => {
    expect(erro(ruleOverrideSchema, { ...overrideBase, justification: '' }, 'justification')).toContain('Justificativa')
    expect(erro(ruleOverrideSchema, { ...overrideBase, rule_code: 'icms' }, 'rule_code')).toContain('PREFIXO.ASSUNTO.DETALHE')
  })
})

describe('rowOverrideSchema', () => {
  it('exige tabela, chave e data de vigência', () => {
    const r = rowOverrideSchema.safeParse({ source_type: 'firm', key: [], data: {}, justification: 'motivo' })
    expect(r.success).toBe(false)
    expect(r.error.issues.map(i => i.path.join('.'))).toEqual(expect.arrayContaining(['reference_table_id', 'key', 'effective_from']))
  })
})

describe('userSchema', () => {
  it('na criação exige senha de 10 caracteres; na edição aceita vazio (mantém a atual)', () => {
    const base = { name: 'Ana', email: 'ana@fiscal.local', role: 'accountant' }
    expect(erro(userSchema(false), { ...base, password: '123' }, 'password')).toContain('10 caracteres')
    expect(userSchema(true).safeParse({ ...base, password: '' }).success).toBe(true)
  })

  it('recusa papel de administrador da plataforma (a API responde 422)', () => {
    expect(erro(userSchema(false), { name: 'Ana', email: 'ana@fiscal.local', role: 'platform_admin', password: 'senha12345' }, 'role')).toBe('Papel inválido')
  })
})

describe('changePasswordSchema', () => {
  it('aponta a confirmação divergente', () => {
    expect(erro(changePasswordSchema, { current_password: 'x', password: 'senha123456', password_confirmation: 'senha123457' }, 'password_confirmation')).toBe('As senhas não conferem')
  })
})

describe('referenceTableSchema', () => {
  it('exige código snake_case e ao menos uma parte da chave', () => {
    expect(erro(referenceTableSchema, { code: 'ST UF', name: 'ST por UF', key_names: [], source_class: 'C', source_url: '' }, 'code')).toContain('snake_case')
    expect(erro(referenceTableSchema, { code: 'st_uf', name: 'ST por UF', key_names: [], source_class: 'C', source_url: '' }, 'key_names')).toContain('parte da chave')
  })
})

describe('referenceVersionSchema / newRuleSchema', () => {
  it('exige vigência na nova versão e normaliza o código da regra', () => {
    expect(erro(referenceVersionSchema, { effective_from: '01/08/2026', copy_from_previous: true }, 'effective_from')).toContain('Data inválida')
    expect(newRuleSchema.parse({ code: 'icms.rate.interstate' }).code).toBe('ICMS.RATE.INTERSTATE')
  })
})
