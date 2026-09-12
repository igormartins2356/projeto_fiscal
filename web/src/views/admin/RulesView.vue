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
import PageHeader from '../../components/PageHeader.vue'
import { adminRules, errorMessage } from '../../api/client'
import { RULE_SCOPES, RULE_STATES, STATE_SEVERITY } from '../../constants/rules'
import { newRuleSchema } from '../../schemas/rule'
import { debounce } from '../../utils/debounce'
import { fmtDate, todayIso } from '../../utils/date'

export default {
  name: 'AdminRulesView',
  components: { PageHeader, Form, Field, Button, InputText, Select, DataTable, Column, Tag, Dialog, FormField },
  data() {
    return { rows: [], total: 0, loading: false, reqId: 0, debouncedSearch: null, lazy: { page: 1, per_page: 25, q: '', state: null, scope: null },
             states: RULE_STATES, scopes: RULE_SCOPES, sev: STATE_SEVERITY, schema: toTypedSchema(newRuleSchema),
             newDialog: false, busy: false }
  },
  created() {
    // Busca por código: uma requisição por pausa de digitação, não por tecla.
    this.debouncedSearch = debounce(() => { this.lazy.page = 1; this.load() }, 300)
    this.load()
  },
  beforeUnmount() { this.debouncedSearch?.cancel() },
  watch: { 'lazy.q'() { this.debouncedSearch() }, 'lazy.state'() { this.lazy.page = 1; this.load() }, 'lazy.scope'() { this.lazy.page = 1; this.load() } },
  methods: {
    fmtDate,
    async load() {
      this.loading = true
      const seq = ++this.reqId
      try {
        const r = await adminRules.list(this.lazy)
        // Só a última requisição escreve na tabela: a anterior pode chegar depois e reexibir o filtro antigo.
        if (seq !== this.reqId) return
        this.rows = r.data; this.total = r.total
      } catch (e) {
        if (seq === this.reqId) this.$toast.add({ severity: 'error', summary: 'Falha ao carregar as regras', detail: errorMessage(e), life: 4000 })
      } finally { if (seq === this.reqId) this.loading = false }
    },
    onPage(e) { this.lazy.page = e.page + 1; this.lazy.per_page = e.rows; this.load() },
    async create(values) {
      this.busy = true
      try { const r = await adminRules.create({ code: values.code, title: values.code, scope: 'item', severity: 'error', effective_from: todayIso() }); this.newDialog = false; this.$router.push(`/admin/rules/${r.id}`) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao criar a regra', detail: errorMessage(e), life: 4000 }) } finally { this.busy = false }
    },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Regras" subtitle="Regras de validação são dados versionados com vigência; o motor só sabe avaliá-las.">
      <template #actions>
        <InputText v-model="lazy.q" placeholder="Buscar por código" aria-label="Buscar por código" />
        <Select v-model="lazy.state" :options="states" placeholder="Estado" aria-label="Filtrar por estado" showClear />
        <Select v-model="lazy.scope" :options="scopes" placeholder="Escopo" aria-label="Filtrar por escopo" showClear />
        <Button label="Nova regra" icon="pi pi-plus" @click="newDialog = true" />
      </template>
    </PageHeader>
    <div class="card">
    <DataTable :value="rows" :loading="loading" lazy paginator :first="(lazy.page - 1) * lazy.per_page" :rows="lazy.per_page" :totalRecords="total" :rowsPerPageOptions="[25, 50, 100]" dataKey="id" @page="onPage"
               selectionMode="single" @row-click="e => $router.push(`/admin/rules/${e.data.id}`)">
      <Column header="Código"><template #body="{ data }"><span class="font-mono text-xs">{{ data.code }}</span> <span class="text-xs text-slate-400">v{{ data.version }}</span></template></Column>
      <Column field="title" header="Título" />
      <Column field="scope" header="Escopo" class="w-36" />
      <Column field="severity" header="Severidade" class="w-28" />
      <Column header="Estado" class="w-28"><template #body="{ data }"><Tag :severity="sev[data.state]" :value="data.state" /></template></Column>
      <Column header="Vigência" class="w-52"><template #body="{ data }"><span class="text-xs">{{ fmtDate(data.effective_from) }} → {{ data.effective_until ? fmtDate(data.effective_until) : 'aberta' }}</span></template></Column>
      <Column header="Origem" class="w-24"><template #body="{ data }"><span class="text-xs">{{ data.source_type }}</span></template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="newDialog" modal header="Nova regra (ou nova versão)">
      <Form :validation-schema="schema" :initial-values="{ code: '' }" @submit="create" v-slot="{ errors, isSubmitting }">
        <p class="text-sm text-slate-600 mb-2">Informe o código no formato <span class="font-mono">PREFIXO.ASSUNTO.DETALHE</span>. Se já existir, será criada uma nova versão copiando a última.</p>
        <Field name="code" v-slot="{ value, handleChange, handleBlur }">
          <FormField label="Código" :error="errors.code"><InputText :modelValue="value" placeholder="ICMS.RATE.INTERSTATE" class="w-full font-mono" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
        </Field>
        <div class="flex justify-end gap-2 pt-3">
          <Button type="button" label="Cancelar" severity="secondary" @click="newDialog = false" />
          <Button type="submit" label="Criar" :loading="isSubmitting || busy" />
        </div>
      </Form>
    </Dialog>
  </div>
</template>
