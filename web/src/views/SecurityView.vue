<script>
import PageHeader from '../components/PageHeader.vue'
import { mapState, mapActions } from 'pinia'
import { Form, Field } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Dialog from 'primevue/dialog'
import FormField from '../components/FormField.vue'
import { useSession } from '../stores/session'
import { auth, errorMessage } from '../api/client'
import { changePasswordSchema, otpDisableSchema, otpEnableSchema } from '../schemas/password'

export default {
  name: 'SecurityView',
  components: { PageHeader, Form, Field, Button, InputText, Message, Dialog, FormField },
  data() {
    return {
      setup: null, backupCodes: null, busy: false, disableVisible: false,
      passwordSchema: toTypedSchema(changePasswordSchema), enableSchema: toTypedSchema(otpEnableSchema), disableSchema: toTypedSchema(otpDisableSchema),
    }
  },
  computed: { ...mapState(useSession, ['user']) },
  methods: {
    ...mapActions(useSession, ['refreshUser']),
    ...mapActions(useSession, { submitPasswordChange: 'changePassword' }),
    toast(severity, summary, detail) { this.$toast.add({ severity, summary, detail, life: 4000 }) },
    async startSetup() { this.busy = true; try { this.setup = await auth.otpSetup() } catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false } },
    async enable(values, { resetForm }) {
      this.busy = true
      try { const r = await auth.otpEnable(values.code); this.backupCodes = r.backup_codes; this.setup = null; resetForm(); await this.refreshUser(); this.toast('success', '2FA ativado') }
      catch (e) { this.toast('error', 'Código inválido', errorMessage(e)) } finally { this.busy = false }
    },
    async confirmDisable(values, { resetForm }) {
      this.busy = true
      try { await auth.otpDisable(values.password, values.code); this.disableVisible = false; resetForm(); await this.refreshUser(); this.toast('success', '2FA desativado') }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false }
    },
    async changePassword(values, { resetForm }) {
      this.busy = true
      try { await this.submitPasswordChange(values.current_password, values.password); resetForm(); this.toast('success', 'Senha alterada', 'As sessões abertas nos outros dispositivos foram encerradas.') }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false }
    },
  },
}
</script>

<template>
  <div class="max-w-2xl">
    <PageHeader title="Segurança" :subtitle="`${user.name} · ${user.email} · ${user.role}`" />

    <section class="card space-y-4">
      <h2 class="card-title">Autenticação em dois fatores (TOTP)</h2>
      <template v-if="backupCodes">
        <Message severity="success">2FA ativado. Guarde os códigos de backup abaixo — cada um vale uma vez e não serão mostrados de novo.</Message>
        <div class="grid grid-cols-4 gap-2 font-mono text-sm"><span v-for="c in backupCodes" :key="c" class="bg-slate-100 rounded px-2 py-1 text-center">{{ c }}</span></div>
        <Button label="Entendi" severity="secondary" size="small" @click="backupCodes = null" />
      </template>
      <template v-else-if="user.otp_enabled">
        <p class="text-sm text-emerald-700">Ativo.</p>
        <Button label="Desativar 2FA" severity="danger" size="small" @click="disableVisible = true" />
      </template>
      <template v-else-if="setup">
        <p class="text-sm text-slate-600">Escaneie o QR code no seu autenticador (Google Authenticator, Authy, 1Password…) e informe o código gerado.</p>
        <div class="flex gap-6 items-start">
          <div class="w-44 h-44 border border-slate-200 rounded p-1 bg-white" v-html="setup.qr_svg"></div>
          <Form class="space-y-3 flex-1" :validation-schema="enableSchema" :initial-values="{ code: '' }" @submit="enable" v-slot="{ errors, isSubmitting }">
            <p class="text-xs text-slate-500">Chave manual: <span class="font-mono break-all">{{ setup.secret }}</span></p>
            <Field name="code" v-slot="{ value, handleChange, handleBlur }">
              <FormField label="Código do autenticador" :error="errors.code"><InputText :modelValue="value" inputmode="numeric" placeholder="000000" autocomplete="one-time-code" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
            </Field>
            <div class="flex gap-2"><Button type="submit" label="Ativar" :loading="isSubmitting || busy" /><Button type="button" label="Cancelar" severity="secondary" @click="setup = null" /></div>
          </Form>
        </div>
      </template>
      <template v-else>
        <p class="text-sm text-slate-600">Recomendado: os XMLs contêm dados fiscais de terceiros.</p>
        <Button label="Ativar 2FA" :loading="busy" @click="startSetup" />
      </template>
    </section>

    <section class="card space-y-3">
      <h2 class="card-title">Alterar senha</h2>
      <Form :validation-schema="passwordSchema" :initial-values="{ current_password: '', password: '', password_confirmation: '' }" @submit="changePassword" v-slot="{ errors, isSubmitting }">
        <div class="grid grid-cols-3 gap-3">
          <Field name="current_password" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Senha atual" :error="errors.current_password"><InputText :modelValue="value" type="password" autocomplete="current-password" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="password" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Nova senha" :error="errors.password" hint="mínimo de 10 caracteres"><InputText :modelValue="value" type="password" autocomplete="new-password" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="password_confirmation" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Confirmar" :error="errors.password_confirmation"><InputText :modelValue="value" type="password" autocomplete="new-password" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
        </div>
        <Button type="submit" label="Alterar" class="mt-3" :loading="isSubmitting || busy" />
      </Form>
    </section>

    <Dialog v-model:visible="disableVisible" modal header="Desativar 2FA">
      <Form :validation-schema="disableSchema" :initial-values="{ password: '', code: '' }" @submit="confirmDisable" v-slot="{ errors, isSubmitting }">
        <div class="space-y-3">
          <Field name="password" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Senha" :error="errors.password"><InputText :modelValue="value" type="password" autocomplete="current-password" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="code" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Código do autenticador" :error="errors.code" hint="ou um código de backup"><InputText :modelValue="value" inputmode="numeric" autocomplete="one-time-code" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="disableVisible = false" />
            <Button type="submit" label="Desativar" severity="danger" :loading="isSubmitting || busy" />
          </div>
        </div>
      </Form>
    </Dialog>
  </div>
</template>
