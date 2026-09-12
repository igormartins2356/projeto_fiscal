import { z } from 'zod'
import { requiredText } from './common'

// Troca de senha: mínimo de 10 caracteres (Accounts::User) e confirmação igual.
export const changePasswordSchema = z.object({
  current_password: requiredText('Senha atual'),
  password: z.string({ required_error: 'Nova senha é obrigatória' }).min(10, 'A senha precisa ter ao menos 10 caracteres'),
  password_confirmation: requiredText('Confirmação'),
}).refine(v => v.password === v.password_confirmation, { path: ['password_confirmation'], message: 'As senhas não conferem' })

// Desativar 2FA exige senha e código TOTP (ou código de backup).
export const otpDisableSchema = z.object({
  password: requiredText('Senha'),
  code: requiredText('Código').min(6, 'Código deve ter ao menos 6 caracteres'),
})
export const otpEnableSchema = z.object({ code: requiredText('Código').regex(/^\d{6}$/, 'Informe os 6 dígitos do autenticador') })
