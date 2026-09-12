<script>
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import Dialog from 'primevue/dialog'
import { Form, Field } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import FormField from '../../components/FormField.vue'
import TagsInput from '../../components/TagsInput.vue'
import PageHeader from '../../components/PageHeader.vue'
import { adminTables, errorMessage } from '../../api/client'
import { referenceTableSchema, SOURCE_CLASSES } from '../../schemas/referenceTable'
import { fmtDate, todayIso } from '../../utils/date'

export default {
  name: 'AdminTablesView',
  components: { PageHeader, Form, Field, Button, InputText, Select, DataTable, Column, Tag, Dialog, FormField, TagsInput },
  data() {
    return { rows: [], loading: false, busy: false, sourceClasses: SOURCE_CLASSES, schema: toTypedSchema(referenceTableSchema),
             dialog: { visible: false, initial: { code: '', name: '', key_names: [], source_class: 'C', source_url: '' } } }
  },
  created() { this.load() },
  methods: {
    fmtDate,
    async load() {
      this.loading = true
      try { this.rows = await adminTables.list() }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao carregar as tabelas', detail: errorMessage(e), life: 4000 }) }
      finally { this.loading = false }
    },
    async create(values) {
      this.busy = true
      try { const t = await adminTables.create(values); this.dialog.visible = false; this.$router.push(`/admin/tables/${t.id}`) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao criar a tabela', detail: errorMessage(e), life: 4000 }) } finally { this.busy = false }
    },
    overdue(t) { return t.next_review_on && t.next_review_on < todayIso() },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Tabelas de referência" subtitle="Alíquotas, códigos e cronogramas: versionados com vigência, importados de fontes oficiais (DATA_SOURCES.md).">
      <template #actions><Button label="Nova tabela" icon="pi pi-plus" @click="dialog.visible = true" /></template>
    </PageHeader>
    <div class="card">
    <DataTable :value="rows" :loading="loading" dataKey="id" selectionMode="single" @row-click="e => $router.push(`/admin/tables/${e.data.id}`)">
      <Column header="Código"><template #body="{ data }"><span class="font-mono text-xs">{{ data.code }}</span></template></Column>
      <Column field="name" header="Nome" />
      <Column header="Chave" class="w-56"><template #body="{ data }"><span class="font-mono text-xs">{{ data.key_names.join(' + ') }}</span></template></Column>
      <Column header="Classe" class="w-20"><template #body="{ data }"><Tag :value="data.source_class" severity="secondary" /></template></Column>
      <Column header="Versão vigente" class="w-56"><template #body="{ data }"><span v-if="data.current_version" class="text-xs">v{{ data.current_version.version }} · {{ fmtDate(data.current_version.effective_from) }}→{{ data.current_version.effective_until ? fmtDate(data.current_version.effective_until) : '…' }}</span><span v-else class="text-xs text-red-700">nenhuma publicada</span></template></Column>
      <Column header="Próx. revisão" class="w-32"><template #body="{ data }"><span class="text-xs" :class="overdue(data) ? 'text-red-700 font-medium' : 'text-slate-500'">{{ data.next_review_on ? fmtDate(data.next_review_on) : '—' }}</span></template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="dialog.visible" modal header="Nova tabela de referência">
      <Form :validation-schema="schema" :initial-values="dialog.initial" @submit="create" v-slot="{ errors, isSubmitting }">
        <div class="space-y-3 text-sm">
          <Field name="code" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Código" :error="errors.code" hint="snake_case, como st_uf"><InputText :modelValue="value" class="w-full font-mono" placeholder="st_uf" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="name" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Nome" :error="errors.name"><InputText :modelValue="value" class="w-full" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <Field name="key_names" v-slot="{ value, handleChange }">
            <FormField label="Partes da chave" :error="errors.key_names"><TagsInput :modelValue="value ?? []" placeholder="uf, cest" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="grid grid-cols-2 gap-3">
            <Field name="source_class" v-slot="{ value, handleChange }">
              <FormField label="Classe da fonte" :error="errors.source_class" hint="DATA_SOURCES.md"><Select :modelValue="value" :options="sourceClasses" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field name="source_url" v-slot="{ value, handleChange, handleBlur }">
              <FormField label="URL da fonte" :error="errors.source_url"><InputText :modelValue="value ?? ''" class="w-full" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
            </Field>
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="dialog.visible = false" />
            <Button type="submit" label="Criar" :loading="isSubmitting || busy" />
          </div>
        </div>
      </Form>
    </Dialog>
  </div>
</template>
