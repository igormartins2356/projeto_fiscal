import { z } from 'zod'
import { isoDate, optionalIsoDate, requiredText } from './common'
import { RULE_SCOPES, RULE_SEVERITIES } from '../constants/rules'

export const RULE_CODE = /^[A-Z0-9_]+(\.[A-Z0-9_]+)+$/

// Nova regra / nova versão: só o código (o resto copia da última versão ou usa padrão).
export const newRuleSchema = z.object({
  code: requiredText('Código').transform(v => v.toUpperCase()).pipe(z.string().regex(RULE_CODE, 'Código no formato PREFIXO.ASSUNTO.DETALHE')),
})

// Metadados editáveis da regra (o corpo DSL é validado pelo backend em Rules::Validator).
export const ruleSchema = z.object({
  title: requiredText('Título', 3),
  scope: z.enum(RULE_SCOPES, { errorMap: () => ({ message: 'Escopo inválido' }) }),
  severity: z.enum(RULE_SEVERITIES, { errorMap: () => ({ message: 'Severidade inválida' }) }),
  effective_from: isoDate,
  effective_until: optionalIsoDate,
  tags: z.array(z.string()).default([]),
})

export const ruleTestCaseSchema = z.object({
  name: requiredText('Nome'),
  reference_date: isoDate,
})
