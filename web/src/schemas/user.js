import { z } from 'zod'
import { requiredText } from './common'

export const USER_ROLES = [{ value: 'accountant', label: 'Contador' }, { value: 'firm_admin', label: 'Administrador da firma' }]

// Senha mínima de 10 caracteres (Accounts::User). Na edição, vazio = manter a atual.
const newPassword = z.string().min(10, 'Senha deve ter ao menos 10 caracteres')
export const userSchema = (editing) => z.object({
  name: requiredText('Nome', 2),
  email: requiredText('E-mail').email('E-mail inválido'),
  role: z.enum(USER_ROLES.map(r => r.value), { errorMap: () => ({ message: 'Papel inválido' }) }),
  password: editing ? newPassword.optional().or(z.literal('')) : newPassword,
})
