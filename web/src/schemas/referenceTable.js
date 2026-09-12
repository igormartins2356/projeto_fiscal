import { z } from 'zod'
import { isoDate, requiredText } from './common'

export const SOURCE_CLASSES = ['A', 'B', 'C', 'D']

export const referenceTableSchema = z.object({
  code: requiredText('Código').regex(/^[a-z][a-z0-9_]*$/, 'Código em snake_case (ex.: st_uf)'),
  name: requiredText('Nome', 3),
  key_names: z.array(z.string()).min(1, 'Informe ao menos uma parte da chave'),
  source_class: z.enum(SOURCE_CLASSES, { errorMap: () => ({ message: 'Classe inválida' }) }),
  source_url: z.string().url('URL inválida').optional().or(z.literal('')),
})

export const referenceVersionSchema = z.object({
  effective_from: isoDate,
  copy_from_previous: z.boolean().default(true),
  notes: z.string().optional().or(z.literal('')),
})
