<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputText from 'primevue/inputtext'
import Message from 'primevue/message'
import Dialog from 'primevue/dialog'
import Textarea from 'primevue/textarea'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import SeverityTag from '../components/SeverityTag.vue'
import { auditRuns, findings, downloadAuditReport, errorMessage } from '../api/client'
import { exportCsv, exportXlsx } from '../utils/export'

export const FINDING_STATES = [
  { value: 'open', label: 'aberto' }, { value: 'justified', label: 'justificado' }, { value: 'false_positive', label: 'falso positivo' },
  { value: 'fixed', label: 'corrigido' }, { value: 'ignored', label: 'ignorado' },
]
const SEVERITIES = [{ value: 'error', label: 'erro' }, { value: 'warning', label: 'alerta' }, { value: 'info', label: 'info' }]
const EXPORT_COLUMNS = [
  { field: 'rule_code', header: 'Regra' }, { field: 'severity', header: 'Severidade' }, { field: 'state', header: 'Situação' },
  { field: 'document', header: 'Documento', value: f => (f.document ? `${f.document.number}/${f.document.series}` : '') },
  { field: 'access_key', header: 'Chave', value: f => f.document?.access_key ?? '' },
  { field: 'item_number', header: 'Item' }, { field: 'message', header: 'Mensagem' },
  { field: 'evidence', header: 'Evidência', value: f => Object.entries(f.evidence ?? {}).map(([k, v]) => `${k}=${v ?? '—'}`).join('; ') },
]

export default {
  name: 'RunDetailView',
  components: { PageHeader, Button, Select, InputText, Message, Dialog, Textarea, DataTable, Column, SeverityTag },
  props: { id: { type: String, required: true } },
  // setup() só registra as queries/mutations do Vue Query; o restante é Options API.
  setup(props) {
    const queryClient = useQueryClient()
    const run = reactive(useQuery({ queryKey: ['audit_run', props.id], queryFn: () => auditRuns.get(props.id), refetchInterval: (q) => (['queued', 'running'].includes(q.state.data?.state) ? 2000 : false) }))
    const update = reactive(useMutation({
      mutationFn: ({ id, state, state_note }) => findings.update(id, { state, state_note }),
      onSuccess: () => queryClient.invalidateQueries({ queryKey: ['findings', props.id] }),
    }))
    return { run, update, queryClient }
  },
  data() {
    return {
      pdfBusy: false,
      rows: [], total: 0, loading: false,
      lazy: { page: 1, per_page: 25, sort_field: 'rule_code', sort_order: 1, filters: { rule_code: null, severity: null, state: null, q: '' } },
      expanded: {},
      states: FINDING_STATES, severities: SEVERITIES,
      dialog: { visible: false, finding: null, state: null, note: '' },
    }
  },
  computed: {
    ruleOptions() {
      const m = new Map()
      for (const g of this.run.data?.groups ?? []) m.set(g.rule_code, (m.get(g.rule_code) ?? 0) + g.count)
      return [...m.entries()].sort((a, b) => b[1] - a[1]).map(([value, n]) => ({ value, label: `${value} (${n})` }))
    },
    done() { return this.run.data?.state === 'done' },
    first() { return (this.lazy.page - 1) * this.lazy.per_page },
  },
  watch: {
    done: { immediate: true, handler(v) { if (v) this.load() } },
    'lazy.filters': { deep: true, handler() { this.lazy.page = 1; this.load() } },
  },
  methods: {
    async load() {
      if (!this.done) return
      this.loading = true
      const { filters, ...rest } = this.lazy
      const params = { ...rest, ...Object.fromEntries(Object.entries(filters).filter(([, v]) => v !== null && v !== '')) }
      try {
        const res = await this.queryClient.fetchQuery({ queryKey: ['findings', this.id, params], queryFn: () => auditRuns.findings(this.id, params), staleTime: 0 })
        this.rows = res.data; this.total = res.total
      } finally { this.loading = false }
    },
    onPage(e) { this.lazy.page = e.page + 1; this.lazy.per_page = e.rows; this.load() },
    onSort(e) { this.lazy.sort_field = e.sortField; this.lazy.sort_order = e.sortOrder; this.load() },
    openStateDialog(f, state) {
      if (state === 'open') return this.saveState(f, state, null)
      this.dialog = { visible: true, finding: f, state, note: f.state_note ?? '' }
    },
    async confirmDialog() {
      await this.saveState(this.dialog.finding, this.dialog.state, this.dialog.note)
      this.dialog.visible = false
    },
    async saveState(f, state, note) {
      try {
        await this.update.mutateAsync({ id: f.id, state, state_note: note })
        await this.load()
        this.$toast.add({ severity: 'success', summary: 'Situação atualizada', detail: `${f.rule_code} → ${this.states.find(s => s.value === state)?.label}`, life: 2500 })
      } catch (e) {
        this.$toast.add({ severity: 'error', summary: 'Falha ao atualizar', detail: e.message, life: 4000 })
      }
    },
    async allRows() {
      const { filters, ...rest } = this.lazy
      const params = { ...rest, page: 1, per_page: 200, ...Object.fromEntries(Object.entries(filters).filter(([, v]) => v !== null && v !== '')) }
      const out = []
      for (let page = 1; ; page++) {
        const res = await auditRuns.findings(this.id, { ...params, page })
        out.push(...res.data)
        if (out.length >= res.total || res.data.length === 0) break
      }
      return out
    },
    async exportCsv() { exportCsv(await this.allRows(), EXPORT_COLUMNS, `auditoria-${this.id}.csv`) },
    async exportXlsx() { await exportXlsx(await this.allRows(), EXPORT_COLUMNS, `auditoria-${this.id}.xlsx`) },
    refresh() { this.run.refetch(); this.load() },
    async downloadPdf() {
      this.pdfBusy = true
      try { await downloadAuditReport(this.id) } catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao gerar PDF', detail: errorMessage(e), life: 4000 }) } finally { this.pdfBusy = false }
    },
    stateLabel(v) { return this.states.find(s => s.value === v)?.label ?? v },
  },
}
</script>

<template>
  <div v-if="run.data">
    <PageHeader :title="`Auditoria #${run.data.id}`" :subtitle="`${run.data.period_start} → ${run.data.period_end} · ${run.data.documents_count} documentos · ${run.data.state}`">
      <template #actions>
        <Button label="Relatório PDF" icon="pi pi-file-pdf" size="small" :loading="pdfBusy" :disabled="run.data.state !== 'done'" @click="downloadPdf" />
        <Button label="CSV" icon="pi pi-file" severity="secondary" outlined size="small" :disabled="!total" @click="exportCsv" />
        <Button label="XLSX" icon="pi pi-file-excel" severity="secondary" outlined size="small" :disabled="!total" @click="exportXlsx" />
        <Button icon="pi pi-refresh" severity="secondary" outlined size="small" aria-label="Atualizar" @click="refresh" />
      </template>
    </PageHeader>
    <Message v-if="run.data.state === 'failed'" severity="error">A auditoria falhou: {{ run.data.evaluation_errors?.[0]?.fatal }}</Message>
    <Message v-else-if="run.data.evaluation_errors?.length" severity="warn">{{ run.data.evaluation_errors.length }} regra(s) com erro de avaliação (ver painel admin).</Message>
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
      <div v-for="sev in ['error', 'warning', 'info']" :key="sev" class="card !mb-0 stat-card">
        <div class="flex items-start justify-between"><span class="stat-label">{{ { error: 'Erros', warning: 'Alertas', info: 'Informativos' }[sev] }}</span><span :class="['stat-icon', { error: 'bg-red-100 text-red-500', warning: 'bg-orange-100 text-orange-500', info: 'bg-blue-100 text-blue-500' }[sev]]"><i :class="['pi', { error: 'pi-times-circle', warning: 'pi-exclamation-triangle', info: 'pi-info-circle' }[sev]]"></i></span></div>
        <span class="stat-value">{{ run.data.summary?.[sev] ?? 0 }}</span>
      </div>
    </div>

    <div class="card">
    <DataTable :value="rows" :loading="loading" lazy paginator :first="first" :rows="lazy.per_page" :totalRecords="total" :rowsPerPageOptions="[10, 25, 50, 100]"
               :sortField="lazy.sort_field" :sortOrder="lazy.sort_order" dataKey="id" v-model:expandedRows="expanded" filterDisplay="row"
               @page="onPage" @sort="onSort">
      <Column expander class="w-10" />
      <Column field="rule_code" header="Regra" sortable :showFilterMenu="false">
        <template #body="{ data }"><span class="font-mono text-xs">{{ data.rule_code }}</span><div class="text-xs text-slate-500">{{ data.rule_title }}</div></template>
        <template #filter><Select v-model="lazy.filters.rule_code" :options="ruleOptions" optionValue="value" optionLabel="label" placeholder="Todas" showClear class="w-full text-xs" /></template>
      </Column>
      <Column field="severity" header="Severidade" sortable :showFilterMenu="false" class="w-36">
        <template #body="{ data }"><SeverityTag :severity="data.severity" /></template>
        <template #filter><Select v-model="lazy.filters.severity" :options="severities" optionValue="value" optionLabel="label" placeholder="Todas" showClear class="w-full text-xs" /></template>
      </Column>
      <Column header="Documento" class="w-44">
        <template #body="{ data }"><template v-if="data.document">NF {{ data.document.number }}/{{ data.document.series }}<span v-if="data.item_number" class="text-slate-500"> · item {{ data.item_number }}</span><div class="text-xs text-slate-500">{{ data.document.nature }}</div></template></template>
      </Column>
      <Column field="message" header="Mensagem" :showFilterMenu="false">
        <template #filter><InputText v-model.lazy="lazy.filters.q" placeholder="Buscar na mensagem" class="text-xs" /></template>
      </Column>
      <Column field="state" header="Situação" sortable :showFilterMenu="false" class="w-44">
        <template #body="{ data }">
          <Select :modelValue="data.state" :options="states" optionValue="value" optionLabel="label" class="w-full text-xs" @update:modelValue="openStateDialog(data, $event)" />
        </template>
        <template #filter><Select v-model="lazy.filters.state" :options="states" optionValue="value" optionLabel="label" placeholder="Todas" showClear class="w-full text-xs" /></template>
      </Column>
      <template #expansion="{ data }">
        <div class="grid grid-cols-2 gap-6 text-sm">
          <div>
            <h4 class="text-xs uppercase text-slate-500 mb-1">Evidência</h4>
            <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs"><template v-for="(v, k) in data.evidence" :key="k"><dt class="font-mono text-slate-600">{{ k }}</dt><dd>{{ v ?? '—' }}</dd></template></dl>
          </div>
          <div class="space-y-1 text-xs">
            <h4 class="uppercase text-slate-500 mb-1">Documento</h4>
            <div v-if="data.document"><span class="text-slate-500">Chave:</span> <span class="font-mono">{{ data.document.access_key }}</span></div>
            <div v-if="data.document"><span class="text-slate-500">Emissão:</span> {{ new Date(data.document.issued_at).toLocaleString('pt-BR') }}</div>
            <div><span class="text-slate-500">Origem da regra:</span> {{ data.rule_source }}</div>
            <div v-if="data.state_note"><span class="text-slate-500">Justificativa:</span> {{ data.state_note }}</div>
          </div>
        </div>
      </template>
      <template #empty><div class="empty-state"><i class="pi pi-check-circle"></i>Nenhum apontamento{{ done ? '' : ' (auditoria em processamento)' }}.</div></template>
    </DataTable>
    </div>

    <Dialog v-model:visible="dialog.visible" modal :header="`Marcar como ${stateLabel(dialog.state)}`">
      <p class="text-slate-600 mb-3">{{ dialog.finding?.message }}</p>
      <label class="block text-xs text-slate-500 mb-1">Justificativa (fica registrada e é reaproveitada nas próximas auditorias)</label>
      <Textarea v-model="dialog.note" rows="3" />
      <template #footer>
        <Button label="Cancelar" severity="secondary" @click="dialog.visible = false" />
        <Button label="Confirmar" :loading="update.isPending" @click="confirmDialog" />
      </template>
    </Dialog>
  </div>
  <div v-else class="card text-secondary">Carregando…</div>
</template>
