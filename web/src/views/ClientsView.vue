<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
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
import { clientsApi, errorMessage } from '../api/client'
import { clientSchema } from '../schemas/client'
import { UFS } from '../schemas/taxScenario'

export default {
  name: 'ClientsView',
  components: { PageHeader, Form, Field, Button, InputText, Select, Dialog, DataTable, Column, Tag, FormField },
  setup() {
    const queryClient = useQueryClient()
    const list = reactive(useQuery({ queryKey: ['clients', 'all'], queryFn: () => clientsApi.list({ include_inactive: 1 }) }))
    const save = reactive(useMutation({
      mutationFn: ({ id, data }) => (id ? clientsApi.update(id, data) : clientsApi.create(data)),
      onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['clients'] }) },
    }))
    return { list, save }
  },
  data() { return { schema: toTypedSchema(clientSchema), ufs: UFS, dialog: { visible: false, id: null, initial: {} } } },
  methods: {
    open(c = null) { this.dialog = { visible: true, id: c?.id ?? null, initial: c ? { cnpj: c.cnpj, legal_name: c.legal_name, trade_name: c.trade_name, uf: c.uf, city_code: c.city_code, ie: c.ie } : { uf: 'SP' } } },
    async submit(values) {
      try { await this.save.mutateAsync({ id: this.dialog.id, data: values }); this.dialog.visible = false; this.$toast.add({ severity: 'success', summary: 'Cliente salvo', life: 2500 }) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha', detail: errorMessage(e), life: 4000 }) }
    },
    fmtCnpj(c) { return c.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5') },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Clientes" subtitle="CNPJs monitorados pelo escritório. Cada cliente tem seu cenário tributário.">
      <template #actions><Button label="Novo cliente" icon="pi pi-plus" @click="open()" /></template>
    </PageHeader>
    <div class="card">
    <DataTable :value="list.data ?? []" :loading="list.isPending" dataKey="id">
      <Column header="CNPJ" class="w-44"><template #body="{ data }"><span class="font-mono text-xs">{{ fmtCnpj(data.cnpj) }}</span></template></Column>
      <Column field="legal_name" header="Razão social" sortable />
      <Column field="uf" header="UF" class="w-16" />
      <Column header="Ativo" class="w-20"><template #body="{ data }"><Tag :severity="data.active ? 'success' : 'secondary'" :value="data.active ? 'sim' : 'não'" /></template></Column>
      <Column class="w-64"><template #body="{ data }">
        <div class="flex gap-1">
          <Button label="Cenário tributário" icon="pi pi-sitemap" size="small" @click="$router.push(`/clients/${data.id}/scenario`)" />
          <Button icon="pi pi-pencil" size="small" severity="secondary" outlined aria-label="Editar" @click="open(data)" />
        </div>
      </template></Column>
    </DataTable>
    </div>

    <Dialog v-model:visible="dialog.visible" modal :header="dialog.id ? 'Editar cliente' : 'Novo cliente'">
      <Form :validation-schema="schema" :initial-values="dialog.initial" @submit="submit" v-slot="{ errors, isSubmitting }">
        <div class="space-y-3">
          <Field name="cnpj" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="CNPJ" :error="errors.cnpj"><InputText :modelValue="value" placeholder="00.000.000/0000-00" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="legal_name" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Razão social" :error="errors.legal_name"><InputText :modelValue="value" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="trade_name" v-slot="{ value, handleChange }">
            <FormField label="Nome fantasia" :error="errors.trade_name"><InputText :modelValue="value ?? ''" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="grid grid-cols-3 gap-3">
            <Field name="uf" v-slot="{ value, handleChange }">
              <FormField label="UF" :error="errors.uf"><Select :modelValue="value" :options="ufs" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field name="city_code" v-slot="{ value, handleChange }">
              <FormField label="Município (IBGE)" :error="errors.city_code"><InputText :modelValue="value ?? ''" placeholder="3550308" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field name="ie" v-slot="{ value, handleChange }">
              <FormField label="Inscrição estadual" :error="errors.ie"><InputText :modelValue="value ?? ''" @update:modelValue="handleChange" /></FormField>
            </Field>
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="dialog.visible = false" />
            <Button type="submit" label="Salvar" :loading="isSubmitting || save.isPending" />
          </div>
        </div>
      </Form>
    </Dialog>
  </div>
</template>
