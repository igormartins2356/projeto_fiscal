<script>
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import Dialog from 'primevue/dialog'
import TagsInput from '../../components/TagsInput.vue'
import PageHeader from '../../components/PageHeader.vue'
import { adminTables, errorMessage } from '../../api/client'

export default {
  name: 'AdminTablesView',
  components: { PageHeader, Button, InputText, Select, DataTable, Column, Tag, Dialog, TagsInput },
  data() { return { rows: [], loading: false, dialog: { visible: false, form: { code: '', name: '', key_names: [], source_class: 'C', source_url: '' } }, busy: false } },
  created() { this.load() },
  methods: {
    async load() { this.loading = true; try { this.rows = await adminTables.list() } finally { this.loading = false } },
    async create() {
      this.busy = true
      try { const t = await adminTables.create(this.dialog.form); this.dialog.visible = false; this.$router.push(`/admin/tables/${t.id}`) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha', detail: errorMessage(e), life: 4000 }) } finally { this.busy = false }
    },
    overdue(t) { return t.next_review_on && t.next_review_on < new Date().toISOString().slice(0, 10) },
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
      <Column header="Versão vigente" class="w-56"><template #body="{ data }"><span v-if="data.current_version" class="text-xs">v{{ data.current_version.version }} · {{ data.current_version.effective_from }}→{{ data.current_version.effective_until ?? '…' }}</span><span v-else class="text-xs text-red-700">nenhuma publicada</span></template></Column>
      <Column header="Próx. revisão" class="w-32"><template #body="{ data }"><span class="text-xs" :class="overdue(data) ? 'text-red-700 font-medium' : 'text-slate-500'">{{ data.next_review_on ?? '—' }}</span></template></Column>
    </DataTable>
    </div>
    <Dialog v-model:visible="dialog.visible" modal header="Nova tabela de referência">
      <div class="space-y-3 text-sm">
        <label class="block">Código<InputText v-model="dialog.form.code" class="w-full mt-1 font-mono" placeholder="st_uf" /></label>
        <label class="block">Nome<InputText v-model="dialog.form.name" class="w-full mt-1" /></label>
        <label class="block">Partes da chave<TagsInput v-model="dialog.form.key_names" class="mt-1" placeholder="uf, cest" /></label>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Classe da fonte<Select v-model="dialog.form.source_class" :options="['A', 'B', 'C', 'D']" class="w-full mt-1" /></label>
          <label class="block">URL da fonte<InputText v-model="dialog.form.source_url" class="w-full mt-1" /></label>
        </div>
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="dialog.visible = false" /><Button label="Criar" :loading="busy" :disabled="!dialog.form.code || !dialog.form.key_names.length" @click="create" /></template>
    </Dialog>
  </div>
</template>
