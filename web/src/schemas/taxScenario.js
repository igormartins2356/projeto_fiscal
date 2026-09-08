// Schema zod do cenário tributário (DSL_RULES.md §7). Reutilizado pelo formulário (vee-validate) e por qualquer validação client-side.
import { z } from 'zod'

export const TAX_REGIMES = [
  { value: 'simples_nacional', label: 'Simples Nacional' },
  { value: 'simples_nacional_excess', label: 'Simples Nacional (excesso de sublimite)' },
  { value: 'lucro_presumido', label: 'Lucro Presumido' },
  { value: 'lucro_real', label: 'Lucro Real' },
  { value: 'mei', label: 'MEI' },
]
export const ACTIVITIES = ['commerce', 'industry', 'service', 'rural']
export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO']

// errorMap em pt-BR (zod 3): cobre ausência, tipo errado e valor fora do enum
const required = (label) => ({
  errorMap: (issue, ctx) => {
    if (issue.code === 'invalid_type' && issue.received === 'undefined') return { message: `${label} é obrigatório` }
    if (issue.code === 'invalid_type' || issue.code === 'invalid_enum_value') return { message: `${label} inválido` }
    return { message: ctx.defaultError }
  },
})
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Data inválida (AAAA-MM-DD)')
const pct = z.string().regex(/^\d{1,3}(\.\d{1,4})?$/, 'Percentual inválido').refine(v => Number(v) <= 100, 'Percentual deve ser ≤ 100')
const ncmPattern = z.string().regex(/^\d{2,8}\*?$/, 'NCM deve ter 2 a 8 dígitos (sufixo * permitido)')

export const benefitSchema = z.object({
  kind: z.enum(['reduced_base', 'presumed_credit', 'deferral', 'exemption', 'suspension'], required('Tipo do benefício')),
  pct: pct.optional(),
  applies_to: z.object({ ncm: z.array(ncmPattern).default([]), cfop: z.array(z.string().regex(/^\d{4}$/, 'CFOP deve ter 4 dígitos')).default([]) }).default({}),
  legal_basis: z.string(required('Base legal')).min(3, 'Informe a base legal'),
  effective_from: isoDate,
  effective_until: isoDate.nullable().optional(),
})

export const stOverrideSchema = z.object({
  ncm: ncmPattern,
  applies: z.boolean(required('Aplicação da ST')),
  legal_basis: z.string(required('Base legal')).min(3, 'Informe a base legal'),
  effective_from: isoDate,
  effective_until: isoDate.nullable().optional(),
})

export const taxScenarioSchema = z.object({
  tax_regime: z.enum(TAX_REGIMES.map(r => r.value), required('Regime tributário')),
  simples_annex: z.enum(['I', 'II', 'III', 'IV', 'V']).optional(),
  uf: z.enum(UFS, required('UF')),
  city_code: z.string().regex(/^\d{7}$/, 'Código IBGE do município deve ter 7 dígitos'),
  icms_taxpayer: z.boolean().default(true),
  ipi_taxpayer: z.boolean().default(false),
  iss_taxpayer: z.boolean().default(false),
  activity: z.array(z.enum(ACTIVITIES)).min(1, 'Informe ao menos uma atividade'),
  cnae: z.object({ primary: z.string().regex(/^\d{7}$/, 'CNAE deve ter 7 dígitos'), secondary: z.array(z.string().regex(/^\d{7}$/, 'CNAE deve ter 7 dígitos')).default([]) }),
  sells_to_final_consumer: z.boolean().default(false),
  uses_nfce: z.boolean().default(false),
  exports: z.boolean().default(false),
  imports: z.boolean().default(false),
  st: z.object({ source: z.enum(['catalog', 'manual']).default('catalog'), applies: z.boolean().default(false), overrides: z.array(stOverrideSchema).default([]) }).default({ source: 'catalog', applies: false, overrides: [] }),
  benefits: z.array(benefitSchema).default([]),
  pis_cofins: z.object({ regime: z.enum(['simples', 'cumulative', 'non_cumulative'], required('Regime de PIS/COFINS')) }),
  ibs_cbs: z.object({ regime: z.enum(['regular', 'simples_nacional_opt_in']).default('regular') }).default({ regime: 'regular' }),
  effective_from: isoDate,
  effective_until: isoDate.nullable().optional(),
}).superRefine((s, ctx) => {
  if (s.tax_regime.startsWith('simples') && s.pis_cofins.regime !== 'simples')
    ctx.addIssue({ code: 'custom', path: ['pis_cofins', 'regime'], message: 'Optante do Simples deve usar regime "simples" em PIS/COFINS' })
  if (s.tax_regime === 'lucro_presumido' && s.pis_cofins.regime === 'non_cumulative')
    ctx.addIssue({ code: 'custom', path: ['pis_cofins', 'regime'], message: 'Lucro Presumido é regime cumulativo de PIS/COFINS' })
  if (s.uses_nfce && !s.sells_to_final_consumer)
    ctx.addIssue({ code: 'custom', path: ['uses_nfce'], message: 'Quem emite NFC-e vende a consumidor final' })
  if (s.effective_until && s.effective_until < s.effective_from)
    ctx.addIssue({ code: 'custom', path: ['effective_until'], message: 'Fim da vigência deve ser posterior ao início' })
})
