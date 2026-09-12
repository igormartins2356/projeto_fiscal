// Blocos reutilizados pelos schemas zod dos formulários (mensagens em pt-BR).
import { z } from 'zod'

export const isoDate = z.string({ required_error: 'Data é obrigatória', invalid_type_error: 'Data inválida' }).regex(/^\d{4}-\d{2}-\d{2}$/, 'Data inválida (AAAA-MM-DD)')
export const optionalIsoDate = isoDate.nullable().optional().or(z.literal(''))
export const requiredText = (label, min = 1) => z.string({ required_error: `${label} é obrigatório`, invalid_type_error: `${label} inválido` }).trim().min(min, min > 1 ? `${label} deve ter ao menos ${min} caracteres` : `${label} é obrigatório`)
export const jsonObject = z.record(z.any(), { invalid_type_error: 'JSON inválido' })
