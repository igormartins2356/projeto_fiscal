<script>
import PageHeader from '../components/PageHeader.vue'
import { mapState, mapActions } from 'pinia'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Dialog from 'primevue/dialog'
import { useSession } from '../stores/session'
import { auth, errorMessage } from '../api/client'

export default {
  name: 'SecurityView',
  components: { PageHeader, Button, InputText, Message, Dialog },
  data() {
    return {
      setup: null, code: '', backupCodes: null, busy: false,
      disable: { visible: false, password: '', code: '' },
      pwd: { current: '', next: '', confirm: '' },
    }
  },
  computed: { ...mapState(useSession, ['user']) },
  methods: {
    ...mapActions(useSession, ['refreshUser']),
    toast(severity, summary, detail) { this.$toast.add({ severity, summary, detail, life: 4000 }) },
    async startSetup() { this.busy = true; try { this.setup = await auth.otpSetup() } catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false } },
    async enable() {
      this.busy = true
      try { const r = await auth.otpEnable(this.code); this.backupCodes = r.backup_codes; this.setup = null; this.code = ''; await this.refreshUser(); this.toast('success', '2FA ativado') }
      catch (e) { this.toast('error', 'Código inválido', errorMessage(e)) } finally { this.busy = false }
    },
    async confirmDisable() {
      this.busy = true
      try { await auth.otpDisable(this.disable.password, this.disable.code); this.disable = { visible: false, password: '', code: '' }; await this.refreshUser(); this.toast('success', '2FA desativado') }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false }
    },
    async changePassword() {
      if (this.pwd.next !== this.pwd.confirm) return this.toast('warn', 'As senhas não conferem')
      if (this.pwd.next.length < 10) return this.toast('warn', 'A senha precisa ter ao menos 10 caracteres')
      this.busy = true
      try { await auth.changePassword(this.pwd.current, this.pwd.next); this.pwd = { current: '', next: '', confirm: '' }; this.toast('success', 'Senha alterada', 'As outras sessões foram encerradas.') }
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
        <Button label="Desativar 2FA" severity="danger" size="small" @click="disable.visible = true" />
      </template>
      <template v-else-if="setup">
        <p class="text-sm text-slate-600">Escaneie o QR code no seu autenticador (Google Authenticator, Authy, 1Password…) e informe o código gerado.</p>
        <div class="flex gap-6 items-start">
          <div class="w-44 h-44 border border-slate-200 rounded p-1 bg-white" v-html="setup.qr_svg"></div>
          <div class="space-y-3 flex-1">
            <p class="text-xs text-slate-500">Chave manual: <span class="font-mono break-all">{{ setup.secret }}</span></p>
            <InputText v-model="code" inputmode="numeric" placeholder="000000" />
            <div class="flex gap-2"><Button label="Ativar" :loading="busy" @click="enable" /><Button label="Cancelar" severity="secondary" @click="setup = null" /></div>
          </div>
        </div>
      </template>
      <template v-else>
        <p class="text-sm text-slate-600">Recomendado: os XMLs contêm dados fiscais de terceiros.</p>
        <Button label="Ativar 2FA" :loading="busy" @click="startSetup" />
      </template>
    </section>

    <section class="card space-y-3">
      <h2 class="card-title">Alterar senha</h2>
      <div class="grid grid-cols-3 gap-3">
        <InputText v-model="pwd.current" type="password" placeholder="Senha atual" autocomplete="current-password" />
        <InputText v-model="pwd.next" type="password" placeholder="Nova senha (mín. 10)" autocomplete="new-password" />
        <InputText v-model="pwd.confirm" type="password" placeholder="Confirmar" autocomplete="new-password" />
      </div>
      <Button label="Alterar" :loading="busy" :disabled="!pwd.current || !pwd.next" @click="changePassword" />
    </section>

    <Dialog v-model:visible="disable.visible" modal header="Desativar 2FA">
      <div class="space-y-3">
        <InputText v-model="disable.password" type="password" placeholder="Senha" />
        <InputText v-model="disable.code" placeholder="Código do autenticador" />
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="disable.visible = false" /><Button label="Desativar" severity="danger" :loading="busy" @click="confirmDisable" /></template>
    </Dialog>
  </div>
</template>
