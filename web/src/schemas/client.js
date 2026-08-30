import { z } from 'zod'
import { UFS } from './taxScenario'

export function validCnpj(raw) {
  const d = String(raw ?? '').replace(/\D/g, '')
  if (d.length !== 14 || /^(\d)\1+$/.test(d)) return false
  const calc = (len) => {
    let sum = 0, pos = len - 7
    for (let i = len; i >= 1; i--) { sum += Number(d[len - i]) * pos--; if (pos < 2) pos = 9 }
    const r = sum % 11
    return r < 2 ? 0 : 11 - r
  }
  return calc(12) === Number(d[12]) && calc(13) === Number(d[13])
}

export const clientSchema = z.object({
  cnpj: z.string({ required_error: 'CNPJ é obrigatório' }).refine(validCnpj, 'CNPJ inválido'),
  legal_name: z.string({ required_error: 'Razão social é obrigatória' }).min(3, 'Razão social muito curta'),
  trade_name: z.string().optional().nullable(),
  uf: z.enum(UFS, { errorMap: () => ({ message: 'UF inválida' }) }),
  city_code: z.string().regex(/^\d{7}$/, 'Código IBGE do município deve ter 7 dígitos').optional().or(z.literal('')).nullable(),
  ie: z.string().optional().nullable(),
})
