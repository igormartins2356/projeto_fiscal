<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { mapState } from 'pinia'
import { Form, Field } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Dialog from 'primevue/dialog'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import FormField from '../components/FormField.vue'
import { users, errorMessage } from '../api/client'
import { useSession } from '../stores/session'
import { z } from 'zod'
import { USER_ROLES, userSchema } from '../schemas/user'
import { fmtDateTime } from '../utils/date'

export default {
  name: 'UsersView',
  components: { PageHeader, Form, Field, Button, InputText, Select, Dialog, DataTable, Column, Tag, FormField },
  setup() {
    const queryClient = useQueryClient()
    const list = reactive(useQuery({ queryKey: ['users'], queryFn: users.list }))
    const invalidate = () => queryClient.invalidateQueries({ queryKey: ['users'] })
    const save = reactive(useMutation({ mutationFn: ({ id, data }) => (id ? users.update(id, data) : users.create(data)), onSuccess: invalidate }))
    const deactivate = reactive(useMutation({ mutationFn: users.deactivate, onSuccess: invalidate }))
    return { list, save, deactivate }
  },
  data() { return { dialog: { visible: false, id: null, initial: {} } } },
  computed: {
    ...mapState(useSession, ['user']),
    // Editando o administrador da plataforma, o papel atual aparece (só leitura no formulário) para não ser
    // rebaixado ao salvar nome/e-mail; criar ou promover para esse papel continua fora da lista (a API responde 422).
    editingPlatformAdmin() { return this.dialog.initial.role === 'platform_admin' },
    roles() { return this.editingPlatformAdmin ? [...USER_ROLES, { value: 'platform_admin', label: 'Admin da plataforma' }] : USER_ROLES },
    // Na edição a senha é opcional (vazio = manter a atual).
    schema() {
      const base = userSchema(!!this.dialog.id)
      return toTypedSchema(this.editingPlatformAdmin ? base.extend({ role: z.literal('platform_admin') }) : base)
    },
  },
  methods: {
    fmtDateTime,
    open(u = null) { this.dialog = { visible: true, id: u?.id ?? null, initial: u ? { name: u.name, email: u.email, role: u.role, password: '' } : { name: '', email: '', role: 'accountant', password: '' } } },
    async submit(values) {
      const data = { ...values }
      if (!data.password) delete data.password
      try { await this.save.mutateAsync({ id: this.dialog.id, data }); this.dialog.visible = false; this.$toast.add({ severity: 'success', summary: 'Usuário salvo', life: 2500 }) }
      // 422 "papel não permitido" (tentativa de criar administrador da plataforma) chega aqui com o texto do backend.
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao salvar o usuário', detail: errorMessage(e), life: 5000 }) }
    },
    remove(u) {
      this.$confirm.require({ message: `Desativar ${u.name}? As sessões serão encerradas.`, header: 'Confirmar', acceptLabel: 'Desativar', rejectLabel: 'Cancelar',
        accept: () => this.deactivate.mutate(u.id) })
    },
    roleLabel(r) { return ({ platform_admin: 'Admin da plataforma', firm_admin: 'Admin da firma', accountant: 'Contador' })[r] ?? r },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Usuários" subtitle="Quem acessa os dados fiscais dos clientes do escritório.">
      <template #actions><Button label="Novo usuário" icon="pi pi-user-plus" @click="open()" /></template>
    </PageHeader>
    <div class="card">
    <DataTable :value="list.data ?? []" :loading="list.isPending" dataKey="id">
      <Column field="name" header="Nome" sortable />
      <Column field="email" header="E-mail" sortable />
      <Column header="Papel"><template #body="{ data }">{{ roleLabel(data.role) }}</template></Column>
      <Column header="2FA" class="w-20"><template #body="{ data }"><Tag :severity="data.otp_enabled ? 'success' : 'secondary'" :value="data.otp_enabled ? 'ativo' : 'não'" /></template></Column>
      <Column header="Ativo" class="w-20"><template #body="{ data }"><Tag :severity="data.active ? 'success' : 'secondary'" :value="data.active ? 'sim' : 'não'" /></template></Column>
      <Column header="Último acesso"><template #body="{ data }"><span class="text-slate-500 text-xs">{{ fmtDateTime(data.last_sign_in_at) || '—' }}</span></template></Column>
      <Column class="w-40"><template #body="{ data }">
        <div class="flex gap-1"><Button label="Editar" size="small" severity="secondary" @click="open(data)" /><Button v-if="data.active && data.id !== user.id" label="Desativar" size="small" severity="danger" @click="remove(data)" /></div>
      </template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="dialog.visible" modal :header="dialog.id ? 'Editar usuário' : 'Novo usuário'">
      <Form :validation-schema="schema" :initial-values="dialog.initial" @submit="submit" v-slot="{ errors, isSubmitting }">
        <div class="space-y-3">
          <Field name="name" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Nome" :error="errors.name"><InputText :modelValue="value" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="email" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="E-mail" :error="errors.email"><InputText :modelValue="value" type="email" autocomplete="email" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="role" v-slot="{ value, handleChange }">
            <FormField label="Papel" :error="errors.role"><Select :modelValue="value" :options="roles" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="password" v-slot="{ value, handleChange, handleBlur }">
            <FormField :label="dialog.id ? 'Nova senha' : 'Senha'" :error="errors.password" :hint="dialog.id ? 'vazio = manter a senha atual (mín. 10 caracteres)' : 'mínimo de 10 caracteres'"><InputText :modelValue="value ?? ''" type="password" autocomplete="new-password" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="dialog.visible = false" />
            <Button type="submit" label="Salvar" :loading="isSubmitting || save.isPending" />
          </div>
        </div>
      </Form>
    </Dialog>
  </div>
</template>
