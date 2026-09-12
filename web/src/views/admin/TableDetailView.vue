<script>
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Checkbox from 'primevue/checkbox'
import { Form, Field } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import FormField from '../../components/FormField.vue'
import PageHeader from '../../components/PageHeader.vue'
import { adminTables, errorMessage } from '../../api/client'
import { referenceVersionSchema } from '../../schemas/referenceTable'
import { debounce } from '../../utils/debounce'
import { fmtDate, todayIso } from '../../utils/date'

const SEV = { draft: 'secondary', published: 'success', retired: 'danger' }

export default {
  name: 'AdminTableDetailView',
  components: { PageHeader, Form, Field, Button, InputText, Select, DataTable, Column, Tag, Dialog, Message, Checkbox, FormField },
  props: { id: { type: String, required: true } },
  data() {
    return { table: null, selected: null, rows: [], total: 0, loading: false, reqId: 0, debouncedSearch: null, lazy: { page: 1, per_page: 50, q: '' }, diff: null, sev: SEV, busy: false,
             versionSchema: toTypedSchema(referenceVersionSchema),
             newVersion: { visible: false, initial: { effective_from: todayIso(), copy_from_previous: true, notes: '' } },
             importDialog: { visible: false, file: null, mode: 'replace', legal_basis: '' }, syncFile: null }
  },
  computed: { canSync() { return ['ncm', 'ibs_cbs_class'].includes(this.table?.code) } },
  created() {
    // Filtro por chave: uma requisição por pausa de digitação, não por tecla.
    this.debouncedSearch = debounce(() => { this.lazy.page = 1; this.loadRows() }, 300)
    this.load()
  },
  beforeUnmount() { this.debouncedSearch?.cancel() },
  watch: { 'lazy.q'() { this.debouncedSearch() } },
  methods: {
    toast(severity, summary, detail) { this.$toast.add({ severity, summary, detail, life: 5000 }) },
    fmtDate,
    async load(keepSelected = true) {
      try {
        this.table = await adminTables.get(this.id)
        const sel = keepSelected && this.selected ? this.table.versions.find(v => v.id === this.selected.id) : null
        await this.select(sel ?? this.table.versions[0] ?? null)
      } catch (e) { this.toast('error', 'Falha ao carregar a tabela', errorMessage(e)) }
    },
    async select(v) {
      this.selected = v; this.diff = null; this.rows = []; this.total = 0
      if (!v) return
      await this.loadRows()
      try { this.diff = await adminTables.diff(this.id, v.id) } catch (e) { this.toast('error', 'Falha ao comparar com a versão anterior', errorMessage(e)) }
    },
    async loadRows() {
      if (!this.selected) return
      this.loading = true
      const seq = ++this.reqId
      try {
        const r = await adminTables.rows(this.id, this.selected.id, this.lazy)
        // Só a última requisição escreve na tabela: a anterior pode chegar depois e reexibir o filtro antigo.
        if (seq !== this.reqId) return
        this.rows = r.data; this.total = r.total
      } catch (e) {
        if (seq === this.reqId) this.toast('error', 'Falha ao carregar as linhas', errorMessage(e))
      } finally { if (seq === this.reqId) this.loading = false }
    },
    onPage(e) { this.lazy.page = e.page + 1; this.lazy.per_page = e.rows; this.loadRows() },
    async createVersion(values) {
      this.busy = true
      try { const v = await adminTables.createVersion(this.id, values); this.newVersion.visible = false; await this.load(false); await this.select(this.table.versions.find(x => x.id === v.id)) }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) } finally { this.busy = false }
    },
    async doImport() {
      this.busy = true
      try { const r = await adminTables.import(this.id, this.selected.id, this.importDialog.file, this.importDialog.mode, this.importDialog.legal_basis); this.importDialog.visible = false; this.toast('success', `${r.imported} linha(s) importada(s)`); await this.load() }
      catch (e) { this.toast('error', 'Falha na importação', errorMessage(e)) } finally { this.busy = false }
    },
    async doSync() {
      this.busy = true
      try { const r = await adminTables.sync(this.id, this.syncFile); this.toast('success', `Versão v${r.version.version} criada com ${r.imported} linha(s)`); this.syncFile = null; await this.load(false) }
      catch (e) { this.toast('error', 'Falha na sincronização', errorMessage(e)) } finally { this.busy = false }
    },
    publish() {
      this.$confirm.require({ header: 'Publicar versão', message: `Publicar v${this.selected.version} vigente a partir de ${fmtDate(this.selected.effective_from)}? A versão anterior será encerrada no dia anterior e as regras passam a usar esta.`, acceptLabel: 'Publicar', rejectLabel: 'Cancelar',
        accept: async () => { try { await adminTables.publish(this.id, this.selected.id); this.toast('success', 'Versão publicada'); await this.load() } catch (e) { this.toast('error', 'Falha', errorMessage(e)) } } })
    },
    // Aposentar encerra a vigência: as regras deixam de encontrar a tabela e passam a acusar erro de avaliação.
    retire() {
      const v = this.selected
      this.$confirm.require({ header: 'Aposentar versão', message: `Aposentar v${v.version}? As regras deixam de usar esta tabela até que outra versão seja publicada.`, acceptLabel: 'Aposentar', rejectLabel: 'Cancelar',
        accept: async () => { try { await adminTables.retire(this.id, v.id); this.toast('success', 'Versão aposentada'); await this.load() } catch (e) { this.toast('error', 'Falha ao aposentar', errorMessage(e)) } } })
    },
    fmt(v) { return JSON.stringify(v) },
  },
}
</script>

<template>
  <div v-if="table">
    <PageHeader :title="table.name">
      <template #subtitle><span class="mono">{{ table.code }}</span> · chave {{ table.key_names.join(' + ') }} · classe {{ table.source_class }}<template v-if="table.source_url"> · fonte: <a :href="table.source_url" target="_blank" class="text-primary underline">{{ table.source_url }}</a></template></template>
      <template #actions>
        <template v-if="canSync">
          <input type="file" accept=".json" class="text-xs" @change="e => syncFile = e.target.files?.[0] ?? null" />
          <Button :label="syncFile ? 'Importar JSON da fonte' : 'Sincronizar da fonte'" icon="pi pi-sync" severity="secondary" outlined size="small" :loading="busy" @click="doSync" />
        </template>
        <Button label="Nova versão" icon="pi pi-plus" size="small" @click="newVersion.visible = true" />
      </template>
    </PageHeader>

    <div class="grid grid-cols-[260px_1fr] gap-6">
      <aside class="card !p-0 divide-y divide-surface self-start">
        <button v-for="v in table.versions" :key="v.id" class="w-full text-left px-3 py-2 text-sm hover:bg-slate-50 cursor-pointer" :class="{ 'bg-blue-50': selected?.id === v.id }" @click="select(v)">
          <div class="flex items-center gap-2"><span class="font-medium">v{{ v.version }}</span><Tag :severity="sev[v.state]" :value="v.state" /></div>
          <div class="text-xs text-slate-500">{{ fmtDate(v.effective_from) }} → {{ v.effective_until ? fmtDate(v.effective_until) : '…' }} · {{ v.rows_count }} linhas</div>
        </button>
        <p v-if="!table.versions.length" class="p-3 text-xs text-slate-500">Nenhuma versão.</p>
      </aside>
      <section v-if="selected" class="card space-y-3">
        <div class="flex items-center gap-2">
          <Tag :severity="sev[selected.state]" :value="selected.state" />
          <span class="text-sm">v{{ selected.version }} · {{ fmtDate(selected.effective_from) }} → {{ selected.effective_until ? fmtDate(selected.effective_until) : 'em aberto' }} · {{ selected.rows_count }} linhas</span>
          <span v-if="selected.notes" class="text-xs text-slate-500">— {{ selected.notes }}</span>
          <div class="ml-auto flex gap-2">
            <Button v-if="selected.state === 'draft'" label="Importar CSV/JSON" size="small" severity="secondary" @click="importDialog.visible = true" />
            <Button v-if="selected.state === 'draft'" label="Publicar" size="small" :disabled="!selected.rows_count" @click="publish" />
            <Button v-if="selected.state === 'published'" label="Aposentar" size="small" severity="danger" text @click="retire" />
          </div>
        </div>
        <Message v-if="diff?.previous" severity="info">Diff vs v{{ diff.previous.version }}: +{{ diff.counts.added }} adicionadas, −{{ diff.counts.removed }} removidas, {{ diff.counts.changed }} alteradas, {{ diff.counts.unchanged }} iguais.</Message>
        <details v-if="diff?.previous && (diff.added.length || diff.removed.length || diff.changed.length)" class="text-xs">
          <summary class="cursor-pointer text-slate-600">Ver diferenças (até 200 por tipo)</summary>
          <div class="grid grid-cols-3 gap-3 mt-2">
            <div><h4 class="font-medium text-emerald-700">Adicionadas</h4><div v-for="r in diff.added" :key="r.key.join('|')" class="font-mono">{{ r.key.join('|') }} → {{ fmt(r.data) }}</div></div>
            <div><h4 class="font-medium text-red-700">Removidas</h4><div v-for="r in diff.removed" :key="r.key.join('|')" class="font-mono">{{ r.key.join('|') }}</div></div>
            <div><h4 class="font-medium text-amber-700">Alteradas</h4><div v-for="r in diff.changed" :key="r.key.join('|')" class="font-mono">{{ r.key.join('|') }}: {{ fmt(r.before) }} → {{ fmt(r.after) }}</div></div>
          </div>
        </details>
        <InputText v-model="lazy.q" placeholder="Filtrar por chave" aria-label="Filtrar por chave" class="w-72" />
        <DataTable :value="rows" :loading="loading" lazy paginator :first="(lazy.page - 1) * lazy.per_page" :rows="lazy.per_page" :totalRecords="total" :rowsPerPageOptions="[50, 100, 200]" dataKey="id" size="small" @page="onPage">
          <Column header="Chave" class="w-64"><template #body="{ data }"><span class="font-mono text-xs">{{ data.key.join(' | ') }}</span></template></Column>
          <Column header="Dados"><template #body="{ data }"><span class="font-mono text-xs">{{ fmt(data.data) }}</span></template></Column>
          <Column header="Vigência da linha" class="w-44"><template #body="{ data }"><span class="text-xs text-slate-500">{{ data.effective_from ? fmtDate(data.effective_from) : '—' }} → {{ data.effective_until ? fmtDate(data.effective_until) : '—' }}</span></template></Column>
          <Column field="legal_basis" header="Base legal" class="w-56"><template #body="{ data }"><span class="text-xs">{{ data.legal_basis ?? '—' }}</span></template></Column>
        </DataTable>
      </section>
    </div>

    <Dialog v-model:visible="newVersion.visible" modal header="Nova versão">
      <Form :validation-schema="versionSchema" :initial-values="newVersion.initial" @submit="createVersion" v-slot="{ errors, isSubmitting }">
        <div class="space-y-3 text-sm">
          <Field name="effective_from" v-slot="{ value, handleChange }">
            <FormField label="Vigente a partir de" :error="errors.effective_from"><InputText :modelValue="value" type="date" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="copy_from_previous" type="checkbox" :value="true" :unchecked-value="false" v-slot="{ value, handleChange }">
            <label class="inline-flex items-center gap-2"><Checkbox :modelValue="value" binary @update:modelValue="handleChange" /> Copiar linhas da versão anterior</label>
          </Field>
          <Field name="notes" v-slot="{ value, handleChange }">
            <FormField label="Notas" :error="errors.notes"><InputText :modelValue="value ?? ''" class="w-full" placeholder="o que mudou e de onde veio" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="newVersion.visible = false" />
            <Button type="submit" label="Criar rascunho" :loading="isSubmitting || busy" />
          </div>
        </div>
      </Form>
    </Dialog>
    <Dialog v-model:visible="importDialog.visible" modal header="Importar linhas">
      <div class="space-y-3 text-sm">
        <p class="text-xs text-slate-500">CSV com cabeçalho <span class="font-mono">{{ table.key_names.join(';') }};…colunas de dados…;legal_basis;effective_from;effective_until</span> ou JSON <span class="font-mono">[{key:[…], data:{…}}]</span>.</p>
        <input type="file" accept=".csv,.json" @change="e => importDialog.file = e.target.files?.[0] ?? null" />
        <Select v-model="importDialog.mode" :options="[{ value: 'replace', label: 'Substituir todas as linhas' }, { value: 'merge', label: 'Mesclar (upsert por chave)' }]" optionValue="value" optionLabel="label" class="w-full" />
        <InputText v-model="importDialog.legal_basis" class="w-full" placeholder="Base legal padrão (opcional)" />
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="importDialog.visible = false" /><Button label="Importar" :loading="busy" :disabled="!importDialog.file" @click="doImport" /></template>
    </Dialog>
  </div>
</template>
