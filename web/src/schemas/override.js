import { z } from 'zod'
import { isoDate, optionalIsoDate, requiredText, jsonObject } from './common'

export const OVERRIDE_ACTIONS = [{ value: 'disable', label: 'Desativar regra' }, { value: 'enable', label: 'Reativar (sobre desativação da firma)' }, { value: 'adjust', label: 'Ajustar (severidade/params/assert/message)' }]
export const OVERRIDE_SOURCES = [{ value: 'firm', label: 'Toda a firma' }, { value: 'client', label: 'Um cliente' }]

const source = {
  source_type: z.enum(['firm', 'client'], { errorMap: () => ({ message: 'Alvo inválido' }) }),
  source_id: z.number({ invalid_type_error: 'Selecione o cliente' }).int().nullable().optional(),
}
// Alvo "cliente" exige o cliente selecionado; "firma" ignora source_id (zerado no envio).
const clientRequired = (v, ctx) => { if (v.source_type === 'client' && v.source_id == null) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['source_id'], message: 'Selecione o cliente' }) }

export const ruleOverrideSchema = z.object({
  rule_code: requiredText('Código da regra').regex(/^[A-Z0-9_]+(\.[A-Z0-9_]+)+$/, 'Código no formato PREFIXO.ASSUNTO.DETALHE'),
  ...source,
  override_action: z.enum(['disable', 'enable', 'adjust'], { errorMap: () => ({ message: 'Ação inválida' }) }),
  patch: jsonObject.default({}),
  effective_from: isoDate,
  effective_until: optionalIsoDate,
  justification: requiredText('Justificativa', 5),
}).superRefine(clientRequired)

export const rowOverrideSchema = z.object({
  reference_table_id: z.number({ required_error: 'Selecione a tabela', invalid_type_error: 'Selecione a tabela' }).int(),
  ...source,
  key: z.array(z.string()).min(1, 'Informe ao menos uma parte da chave'),
  data: jsonObject.default({}),
  effective_from: isoDate,
  effective_until: optionalIsoDate,
  legal_basis: z.string().optional().nullable(),
  justification: requiredText('Justificativa', 5),
}).superRefine(clientRequired)
