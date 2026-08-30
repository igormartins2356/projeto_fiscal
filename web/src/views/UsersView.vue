<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { mapState } from 'pinia'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Dialog from 'primevue/dialog'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import { users, errorMessage } from '../api/client'
import { useSession } from '../stores/session'

const ROLES = [{ value: 'accountant', label: 'Contador' }, { value: 'firm_admin', label: 'Administrador da firma' }]

export default {
  name: 'UsersView',
  components: { PageHeader, Button, InputText, Select, Dialog, DataTable, Column, Tag },
  setup() {
    const queryClient = useQueryClient()
    const list = reactive(useQuery({ queryKey: ['users'], queryFn: users.list }))
    const invalidate = () => queryClient.invalidateQueries({ queryKey: ['users'] })
    const save = reactive(useMutation({ mutationFn: ({ id, data }) => (id ? users.update(id, data) : users.create(data)), onSuccess: invalidate }))
    const deactivate = reactive(useMutation({ mutationFn: users.deactivate, onSuccess: invalidate }))
    return { list, save, deactivate }
  },
  data() { return { roles: ROLES, dialog: { visible: false, id: null, form: {} } } },
  computed: { ...mapState(useSession, ['user']) },
  methods: {
    open(u = null) { this.dialog = { visible: true, id: u?.id ?? null, form: u ? { name: u.name, email: u.email, role: u.role, password: '' } : { name: '', email: '', role: 'accountant', password: '' } } },
    async submit() {
      const data = { ...this.dialog.form }
      if (!data.password) delete data.password
      try { await this.save.mutateAsync({ id: this.dialog.id, data }); this.dialog.visible = false; this.$toast.add({ severity: 'success', summary: 'Usuário salvo', life: 2500 }) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha', detail: errorMessage(e), life: 4000 }) }
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
      <Column header="Último acesso"><template #body="{ data }"><span class="text-slate-500 text-xs">{{ data.last_sign_in_at ? new Date(data.last_sign_in_at).toLocaleString('pt-BR') : '—' }}</span></template></Column>
      <Column class="w-40"><template #body="{ data }">
        <div class="flex gap-1"><Button label="Editar" size="small" severity="secondary" @click="open(data)" /><Button v-if="data.active && data.id !== user.id" label="Desativar" size="small" severity="danger" @click="remove(data)" /></div>
      </template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="dialog.visible" modal :header="dialog.id ? 'Editar usuário' : 'Novo usuário'">
      <div class="space-y-3">
        <InputText v-model="dialog.form.name" placeholder="Nome" />
        <InputText v-model="dialog.form.email" type="email" placeholder="E-mail" />
        <Select v-model="dialog.form.role" :options="roles" optionValue="value" optionLabel="label" class="w-full" />
        <InputText v-model="dialog.form.password" type="password" :placeholder="dialog.id ? 'Nova senha (opcional, mín. 10)' : 'Senha (mín. 10)'" autocomplete="new-password" />
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="dialog.visible = false" /><Button label="Salvar" :loading="save.isPending" @click="submit" /></template>
    </Dialog>
  </div>
</template>
