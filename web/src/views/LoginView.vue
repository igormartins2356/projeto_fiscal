<script>
import { mapActions, mapState } from 'pinia'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import { useSession } from '../stores/session'
import { errorMessage } from '../api/client'

export default {
  name: 'LoginView',
  components: { Button, InputText, Message },
  data() { return { email: '', password: '', code: '', step: 'credentials', error: null, busy: false } },
  computed: { ...mapState(useSession, ['mfaToken']), expired() { return this.$route.query.expired === '1' } },
  methods: {
    ...mapActions(useSession, ['login', 'mfa']),
    async submit() {
      this.busy = true; this.error = null
      try {
        if (this.step === 'credentials') {
          const r = await this.login(this.email, this.password)
          if (r.mfa) { this.step = 'mfa'; return }
        } else {
          await this.mfa(this.code)
        }
        this.$router.push(this.$route.query.redirect ?? '/')
      } catch (e) {
        this.error = errorMessage(e)
        if (e?.response?.status === 401 && this.step === 'mfa' && /expirado/.test(this.error)) this.step = 'credentials'
      } finally { this.busy = false }
    },
  },
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center p-4">
    <form class="w-full max-w-md card space-y-5" @submit.prevent="submit">
      <div class="flex flex-col items-center gap-2 mb-2">
        <span class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary text-white"><i class="pi pi-verified text-2xl"></i></span>
        <h1 class="text-2xl font-semibold">Validador Fiscal</h1>
        <p class="text-secondary">{{ step === 'credentials' ? 'Entre com sua conta' : 'Verificação em dois fatores' }}</p>
      </div>
      <Message v-if="expired && !error" severity="warn">Sua sessão expirou. Entre novamente.</Message>
      <Message v-if="error" severity="error">{{ error }}</Message>
      <template v-if="step === 'credentials'">
        <div class="field"><label for="email">E-mail</label><InputText id="email" v-model="email" type="email" autocomplete="username" class="w-full" required /></div>
        <div class="field"><label for="password">Senha</label><InputText id="password" v-model="password" type="password" autocomplete="current-password" class="w-full" required /></div>
      </template>
      <template v-else>
        <div class="field"><label for="code">Código do autenticador (ou de backup)</label><InputText id="code" v-model="code" inputmode="numeric" autocomplete="one-time-code" placeholder="000000" class="w-full text-center text-xl tracking-[.4em]" autofocus required /></div>
      </template>
      <Button type="submit" :label="step === 'credentials' ? 'Entrar' : 'Confirmar'" icon="pi pi-sign-in" :loading="busy" class="w-full" />
    </form>
  </div>
</template>
