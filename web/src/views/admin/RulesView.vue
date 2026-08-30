<script>
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import Dialog from 'primevue/dialog'
import PageHeader from '../../components/PageHeader.vue'
import { adminRules, errorMessage } from '../../api/client'

const STATES = ['draft', 'testing', 'shadow', 'published', 'retired']
const SCOPES = ['item', 'document', 'cross_document', 'period', 'scenario']
export const STATE_SEVERITY = { draft: 'secondary', testing: 'info', shadow: 'warn', published: 'success', retired: 'danger' }

export default {
  name: 'AdminRulesView',
  components: { PageHeader, Button, InputText, Select, DataTable, Column, Tag, Dialog },
  data() {
    return { rows: [], total: 0, loading: false, lazy: { page: 1, per_page: 25, q: '', state: null, scope: null }, states: STATES, scopes: SCOPES, sev: STATE_SEVERITY,
             newDialog: false, newCode: '', busy: false }
  },
  created() { this.load() },
  watch: { 'lazy.q'() { this.lazy.page = 1; this.load() }, 'lazy.state'() { this.lazy.page = 1; this.load() }, 'lazy.scope'() { this.lazy.page = 1; this.load() } },
  methods: {
    async load() {
      this.loading = true
      try { const r = await adminRules.list(this.lazy); this.rows = r.data; this.total = r.total } finally { this.loading = false }
    },
    onPage(e) { this.lazy.page = e.page + 1; this.lazy.per_page = e.rows; this.load() },
    async create() {
      this.busy = true
      try { const r = await adminRules.create({ code: this.newCode.trim().toUpperCase(), title: this.newCode, scope: 'item', severity: 'error', effective_from: new Date().toISOString().slice(0, 10) }); this.newDialog = false; this.$router.push(`/admin/rules/${r.id}`) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha', detail: errorMessage(e), life: 4000 }) } finally { this.busy = false }
    },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Regras" subtitle="Regras de validação são dados versionados com vigência; o motor só sabe avaliá-las.">
      <template #actions>
        <InputText v-model.lazy="lazy.q" placeholder="Buscar por código" />
        <Select v-model="lazy.state" :options="states" placeholder="Estado" showClear />
        <Select v-model="lazy.scope" :options="scopes" placeholder="Escopo" showClear />
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
      <Column header="Vigência" class="w-52"><template #body="{ data }"><span class="text-xs">{{ data.effective_from }} → {{ data.effective_until ?? 'aberta' }}</span></template></Column>
      <Column header="Origem" class="w-24"><template #body="{ data }"><span class="text-xs">{{ data.source_type }}</span></template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="newDialog" modal header="Nova regra (ou nova versão)">
      <p class="text-sm text-slate-600 mb-2">Informe o código no formato <span class="font-mono">PREFIXO.ASSUNTO.DETALHE</span>. Se já existir, será criada uma nova versão copiando a última.</p>
      <InputText v-model="newCode" placeholder="ICMS.RATE.INTERSTATE" class="w-full font-mono" />
      <template #footer><Button label="Cancelar" severity="secondary" @click="newDialog = false" /><Button label="Criar" :loading="busy" :disabled="!newCode" @click="create" /></template>
    </Dialog>
  </div>
</template>
